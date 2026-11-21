import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../meds/presentation/meds_providers.dart';
import '../../../push/push_service.dart';
import '../../data/bp_reminder_plan.dart';
import '../../data/bp_reminder_service.dart';
import 'bp_providers.dart';
import '../../../../shared/honorific.dart';

final bpReminderServiceProvider = Provider<BpReminderService>(
  (ref) => BpReminderService(ref.watch(medAlarmServiceProvider)),
);

class BpReminderSettingsNotifier extends AsyncNotifier<BpReminderSettings> {
  @override
  Future<BpReminderSettings> build() => BpReminderSettings.load();

  Future<void> _set(BpReminderSettings next) async {
    state = AsyncData(next);
    await next.save();
  }

  BpReminderSettings get _cur => state.value ?? const BpReminderSettings();

  Future<void> setEnabled(bool v) => _set(_cur.copyWith(enabled: v));
  Future<void> setMorning(String hm) => _set(_cur.copyWith(morning: hm));

  /// null = bỏ nhắc buổi tối.
  Future<void> setEvening(String? hm) => _set(_cur.copyWith(evening: (v: hm)));
}

final bpReminderSettingsProvider =
    AsyncNotifierProvider<BpReminderSettingsNotifier, BpReminderSettings>(
      BpReminderSettingsNotifier.new,
    );

/// Giữ thông báo nhắc đo huyết áp khớp với cài đặt, số đo hôm nay và giờ yên tĩnh.
/// Đặt lại khi mở app, khi có số đo mới, khi đổi cài đặt. (Khởi động lại máy do plugin tự khôi phục.)
class BpReminderHost extends ConsumerStatefulWidget {
  const BpReminderHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BpReminderHost> createState() => _BpReminderHostState();
}

class _BpReminderHostState extends ConsumerState<BpReminderHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(bpReadingsProvider);
      _sync();
    }
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final user = ref.read(currentUserProvider);
    final settings = ref.read(bpReminderSettingsProvider).value;
    if (user == null || settings == null) return;
    final readings = ref.read(bpReadingsProvider).value;
    if (readings == null) return; // chờ có dữ liệu thật để biết hôm nay đã đo chưa
    final now = DateTime.now();
    final prefs = ref.read(pushPrefsProvider).value;
    final elder = user.role == AppRole.elder;
    await ref
        .read(bpReminderServiceProvider)
        .sync(
          enabled: settings.effectiveEnabled(elder: elder),
          slots: settings.slots,
          measuredToday: readings.any((r) => sameDay(r.measuredAt, now)),
          quietStart: prefs?.quietStart,
          quietEnd: prefs?.quietEnd,
          hon: elder ? honorific : 'bạn',
          now: now,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bpReadingsProvider, (_, _) => _sync());
    ref.listen(bpReminderSettingsProvider, (_, _) => _sync());
    ref.listen(pushPrefsProvider, (_, _) => _sync());
    ref.listen(currentUserProvider, (_, _) => _sync());
    return widget.child;
  }
}
