import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/meds_models.dart';

/// Bộ đặt báo thức nhắc uống thuốc trên chính máy (không cần mạng). Mỗi lần đến giờ kêu 3 lần cách nhau 2 phút
/// cho tới khi bác bấm "Đã uống". Lịch lấy từ máy chủ rồi đặt trước tối đa 4 ngày; mỗi lần mở app hoặc khi lịch đổi thì đặt lại.
class MedAlarmService {
  MedAlarmService([FlutterLocalNotificationsPlugin? plugin])
    : _p = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _p;
  bool _ready = false;

  static const channelId = 'viegrand_meds';
  static const payload = 'meds';

  /// Số lần kêu cho mỗi lần uống và khoảng cách giữa các lần.
  static const rings = 3;
  static const ringGap = Duration(minutes: 2);

  /// Giới hạn số lần uống được đặt trước (mỗi lần = [rings] báo thức).
  static const maxDoses = 40;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'Nhắc uống thuốc',
      channelDescription: 'Báo thức đến giờ uống thuốc',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    ),
  );

  /// Id từ đây trở lên dành cho các thông báo khác (nhắc đo huyết áp); báo thức thuốc chỉ dùng id nhỏ hơn.
  static const reservedIdStart = 2100000000;

  Future<void>? _initFuture;

  /// Khởi tạo plugin một lần (gọi lại trả về cùng kết quả; `onTap` của lần gọi đầu được dùng cho mọi thông báo).
  Future<void> init({void Function(String? payload)? onTap}) =>
      _initFuture ??= _init(onTap);

  Future<void> _init(void Function(String? payload)? onTap) async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      await _p.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_viegrand'),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      _ready = true;
      final launch = await _p.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true)
        onTap?.call(launch!.notificationResponse?.payload);
    } catch (e) {
      debugPrint('MedAlarmService.init: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _p
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Xin quyền thông báo và báo thức chính xác. Trả về true nếu cả hai đã được cấp.
  Future<bool> requestPermissions() async {
    try {
      final a = _android;
      if (a == null) return false;
      final n = await a.requestNotificationsPermission() ?? true;
      var exact = await a.canScheduleExactNotifications() ?? false;
      if (!exact) exact = await a.requestExactAlarmsPermission() ?? false;
      return n && exact;
    } catch (_) {
      return false;
    }
  }

  /// Báo thức chính xác có đang được phép không (bác có thể đã tắt trong cài đặt máy).
  Future<bool> exactAllowed() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  static int _baseId(String doseId) =>
      (doseId.hashCode & 0x1fffffff) % 500000000 * 4;

  /// Đặt lại toàn bộ báo thức theo danh sách lần uống [doses] (chỉ lấy các lần còn chờ và ở tương lai).
  /// Trả về số lần uống đã đặt.
  Future<int> sync(
    List<Dose> doses, {
    String hon = 'bác',
    DateTime? now,
  }) async {
    if (!_ready) return 0;
    final t = now ?? DateTime.now();
    try {
      for (final r in await _p.pendingNotificationRequests()) {
        if (r.id < reservedIdStart) await _p.cancel(r.id);
      }
      final upcoming =
          doses
              .where(
                (d) =>
                    d.status == 'pending' &&
                    d.dueAt.isAfter(t) &&
                    !d.dueAt.isAfter(t.add(const Duration(days: 4))),
              )
              .toList()
            ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      var n = 0;
      for (final d in upcoming.take(maxDoses)) {
        for (var k = 0; k < rings; k++) {
          final at = d.dueAt.add(ringGap * k);
          if (!at.isAfter(t)) continue;
          await _p.zonedSchedule(
            _baseId(d.id) + k,
            k == 0 ? 'Đến giờ uống thuốc' : 'Nhắc lại: chưa uống thuốc',
            '${d.hm} · ${_cap(hon)} lấy ${d.what} nhé',
            tz.TZDateTime.from(at, tz.local),
            _details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: payload,
          );
        }
        n++;
      }
      return n;
    } catch (e) {
      debugPrint('MedAlarmService.sync: $e');
      return 0;
    }
  }

  /// Huỷ báo thức của một lần uống (khi đã uống hoặc bỏ qua).
  Future<void> cancelDose(String doseId) async {
    if (!_ready) return;
    try {
      for (var k = 0; k < rings; k++) {
        await _p.cancel(_baseId(doseId) + k);
      }
    } catch (_) {}
  }

  /// Số báo thức đang chờ (để kiểm tra).
  Future<int> pendingCount() async {
    try {
      return (await _p.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
