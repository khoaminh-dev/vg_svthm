import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/analytics/analytics.dart';
import '../../meds/data/med_alarm_service.dart';
import 'bp_reminder_plan.dart';

/// Cài đặt nhắc đo huyết áp lưu trên máy.
class BpReminderSettings {
  const BpReminderSettings({
    this.enabled,
    this.morning = '08:00',
    this.evening,
  });

  /// null = chưa chọn: mặc định bật cho người cao tuổi, tắt cho người thân.
  final bool? enabled;
  final String morning;

  /// Giờ buổi tối (null = không nhắc buổi tối).
  final String? evening;

  bool effectiveEnabled({required bool elder}) => enabled ?? elder;

  Map<String, String> get slots => {
    'morning': morning,
    'evening': ?evening,
  };

  BpReminderSettings copyWith({
    bool? enabled,
    String? morning,
    ({String? v})? evening,
  }) => BpReminderSettings(
    enabled: enabled ?? this.enabled,
    morning: morning ?? this.morning,
    evening: evening != null ? evening.v : this.evening,
  );

  static Future<BpReminderSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return BpReminderSettings(
        enabled: p.getBool(_kEnabled),
        morning: p.getString(_kMorning) ?? '08:00',
        evening: p.getString(_kEvening),
      );
    } catch (_) {
      return const BpReminderSettings();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (enabled == null) {
        await p.remove(_kEnabled);
      } else {
        await p.setBool(_kEnabled, enabled!);
      }
      await p.setString(_kMorning, morning);
      if (evening == null) {
        await p.remove(_kEvening);
      } else {
        await p.setString(_kEvening, evening!);
      }
    } catch (e) {
      debugPrint('BpReminderSettings.save: $e');
    }
  }
}

const _kEnabled = 'bp_rem_enabled';
const _kMorning = 'bp_rem_morning';
const _kEvening = 'bp_rem_evening';
const _kPlan = 'bp_rem_plan';
const _kShownUntil = 'bp_rem_shown_until';

/// Đặt thông báo cục bộ nhắc đo huyết áp (dùng chung plugin đã khởi tạo bởi [MedAlarmService]).
class BpReminderService {
  BpReminderService(this._meds, [FlutterLocalNotificationsPlugin? plugin])
    : _p = plugin ?? FlutterLocalNotificationsPlugin();

  final MedAlarmService _meds;
  final FlutterLocalNotificationsPlugin _p;

  static const channelId = 'viegrand_bp_reminder';
  static const payload = 'bp-reminder';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'Nhắc đo huyết áp',
      channelDescription: 'Nhắc đo huyết áp mỗi ngày',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    ),
  );

  /// Đặt lại toàn bộ nhắc. [enabled] false thì chỉ huỷ. Ghi sự kiện `measure_reminder_shown` cho các lần
  /// đã đến giờ kể từ lần đặt trước. Trả về số thông báo đã đặt.
  Future<int> sync({
    required bool enabled,
    required Map<String, String> slots,
    required bool measuredToday,
    String? quietStart,
    String? quietEnd,
    String hon = 'bác',
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    try {
      await _meds.init();
      final prefs = await SharedPreferences.getInstance();
      await _trackShown(prefs, t);
      for (final r in await _p.pendingNotificationRequests()) {
        if (r.id >= MedAlarmService.reservedIdStart) await _p.cancel(r.id);
      }
      final plan = enabled
          ? planBpReminders(
              now: t,
              slots: slots,
              measuredToday: measuredToday,
              quietStart: quietStart,
              quietEnd: quietEnd,
            )
          : <PlannedReminder>[];
      var n = 0;
      for (final r in plan) {
        await _p.zonedSchedule(
          MedAlarmService.reservedIdStart + r.id,
          r.followUp ? 'Nhắc lại: chưa đo huyết áp' : 'Đến giờ đo huyết áp',
          r.followUp
              ? '${_cap(hon)} ngồi yên 5 phút rồi đo một lần cho yên tâm nhé'
              : '${_cap(hon)} ngồi yên, tựa lưng 5 phút rồi đo huyết áp nhé',
          tz.TZDateTime.from(r.at, tz.local),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        n++;
      }
      await prefs.setString(_kPlan, jsonEncode(plan.map((e) => e.toJson()).toList()));
      return n;
    } catch (e) {
      debugPrint('BpReminderService.sync: $e');
      return 0;
    }
  }

  Future<void> _trackShown(SharedPreferences prefs, DateTime now) async {
    final untilStr = prefs.getString(_kShownUntil);
    final since = DateTime.tryParse(untilStr ?? '') ?? now;
    await prefs.setString(_kShownUntil, now.toIso8601String());
    final raw = prefs.getString(_kPlan);
    if (raw == null) return;
    final stored = <PlannedReminder>[];
    try {
      for (final j in jsonDecode(raw) as List) {
        final r = PlannedReminder.fromJson(j);
        if (r != null) stored.add(r);
      }
    } catch (_) {}
    for (final r in remindersShown(stored, since, now)) {
      Analytics.track('measure_reminder_shown', {
        'slot': r.slot,
        'follow_up': r.followUp,
      });
    }
  }

  /// Gọi khi bấm vào thông báo nhắc.
  static void trackOpened() => Analytics.track('measure_reminder_opened');

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
