import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../meds/presentation/meds_providers.dart';

/// Nhắc việc do người dùng nhờ Vy đặt bằng giọng ("nhắc tôi 8 giờ sáng mai đi khám"), lưu trên máy (quyết định Q4).
/// Đến giờ: Vy nhắc ngay khi app đang mở (bộ nhắc chủ động) và thông báo hệ điều hành khi app ở nền.
class UserReminder {
  const UserReminder({required this.id, required this.at, required this.what, this.done = false});

  final int id;
  final DateTime at;
  final String what;

  /// Đã nhắc xong (hoặc người dùng đã bấm "Xong").
  final bool done;

  UserReminder copyWith({DateTime? at, bool? done}) => UserReminder(id: id, at: at ?? this.at, what: what, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'at': at.millisecondsSinceEpoch, 'what': what, if (done) 'done': true};

  static UserReminder? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'], at = o['at'], what = o['what'];
    if (id is! num || at is! num || what is! String || what.isEmpty) return null;
    return UserReminder(id: id.toInt(), at: DateTime.fromMillisecondsSinceEpoch(at.toInt()), what: what, done: o['done'] == true);
  }
}

/// Dải mã thông báo dành riêng (dưới `reservedIdStart` của nhắc đo huyết áp, và được báo thức thuốc bỏ qua khi dọn).
const userReminderIdBase = 2050000000;
const userReminderIdSpan = 100000;

bool isUserReminderNotificationId(int id) => id >= userReminderIdBase && id < userReminderIdBase + userReminderIdSpan;

const maxPendingReminders = 20;

/// Mã chống nhắc lặp cho bộ nhắc chủ động.
String userReminderKey(UserReminder r) => 'user:${r.id}:${r.at.millisecondsSinceEpoch}';

/// Nhắc việc đã đến giờ nhưng chưa nhắc: trong vòng [window] sau giờ hẹn (quá lâu thì thôi, đỡ nhắc chuyện đã cũ).
const reminderWindow = Duration(hours: 4);

UserReminder? dueReminder(List<UserReminder> list, DateTime now) {
  UserReminder? best;
  for (final r in list) {
    if (r.done || now.isBefore(r.at) || now.difference(r.at) > reminderWindow) continue;
    if (best == null || r.at.isBefore(best.at)) best = r;
  }
  return best;
}

class UserRemindersNotifier extends Notifier<List<UserReminder>> {
  static const _key = 'user_reminders_v1';
  static const _channelId = 'viegrand_user_reminder';

  @override
  List<UserReminder> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final list = [for (final o in jsonDecode(raw) as List) ?UserReminder.fromJson(o)];
      final have = {for (final r in state) r.id};
      state = _tidy([...state, ...list.where((r) => !have.contains(r.id))], DateTime.now());
    } catch (_) {}
  }

  /// Bỏ việc đã xong hoặc đã cũ quá một ngày; giữ tối đa [maxPendingReminders] việc còn chờ.
  List<UserReminder> _tidy(List<UserReminder> l, DateTime now) {
    final keep = [
      for (final r in l)
        if (!(r.done && now.difference(r.at) > const Duration(hours: 1)) && now.difference(r.at) < const Duration(days: 1)) r,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return keep;
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final r in state) r.toJson()]));
    } catch (_) {}
  }

  /// Số việc đang chờ (chưa xong, chưa tới giờ hoặc đang trong cửa sổ nhắc).
  int get pendingCount => state.where((r) => !r.done).length;

  /// Đặt một nhắc việc. Trả về null nếu đã đủ [maxPendingReminders] việc chờ.
  UserReminder? add(DateTime at, String what, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (pendingCount >= maxPendingReminders) return null;
    final id = (state.isEmpty ? 0 : state.map((r) => r.id).reduce((a, b) => a > b ? a : b)) + 1;
    final r = UserReminder(id: id, at: at, what: what.trim());
    state = _tidy([...state, r], t);
    unawaited(_save());
    unawaited(_schedule(r));
    return r;
  }

  void markDone(int id) {
    state = [for (final r in state) r.id == id ? r.copyWith(done: true) : r];
    unawaited(_save());
    unawaited(_cancel(id));
  }

  /// "Nhắc lại sau [minutes] phút".
  void snooze(int id, int minutes, {DateTime? now}) {
    final t = (now ?? DateTime.now()).add(Duration(minutes: minutes));
    state = [for (final r in state) r.id == id ? r.copyWith(at: t, done: false) : r];
    unawaited(_save());
    final r = state.where((x) => x.id == id).firstOrNull;
    if (r != null) unawaited(_schedule(r));
  }

  UserReminder? due(DateTime now) => dueReminder(state, now);

  Future<void> _schedule(UserReminder r) async {
    try {
      final svc = ref.read(medAlarmServiceProvider);
      await svc.init();
      final p = FlutterLocalNotificationsPlugin();
      await p.zonedSchedule(
        userReminderIdBase + (r.id % userReminderIdSpan),
        'Nhắc việc',
        r.what,
        tz.TZDateTime.from(r.at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Nhắc việc',
            channelDescription: 'Việc bạn nhờ Vy nhắc',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            autoCancel: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('UserReminders.schedule: $e');
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(userReminderIdBase + (id % userReminderIdSpan));
    } catch (_) {}
  }
}

final userRemindersProvider = NotifierProvider<UserRemindersNotifier, List<UserReminder>>(UserRemindersNotifier.new);

/// Nói giờ đã đặt: "8 giờ sáng mai", "3 giờ 30 chiều nay", "7 giờ tối ngày 26 tháng 11".
String spokenWhen(DateTime at, DateTime now) {
  final h = at.hour;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final part = h < 5 ? 'đêm' : h < 11 ? 'sáng' : h < 13 ? 'trưa' : h < 18 ? 'chiều' : h < 22 ? 'tối' : 'đêm';
  final m = at.minute == 0 ? '' : at.minute == 30 ? ' rưỡi' : ' ${at.minute} phút';
  final days = DateTime(at.year, at.month, at.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => 'nay',
    1 => 'mai',
    2 => 'ngày kia',
    _ => 'ngày ${at.day} tháng ${at.month}',
  };
  if (days == 0 || days == 1) return '$h12 giờ$m $part $day';
  return '$h12 giờ$m $part $day';
}
