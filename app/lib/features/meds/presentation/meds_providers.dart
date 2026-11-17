import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/data/bp_reminder_service.dart';
import '../../bp/presentation/providers/bp_reminder_providers.dart';
import '../../health/presentation/providers/health_providers.dart';
import 'package:image_picker/image_picker.dart';

import '../data/med_alarm_service.dart';
import '../data/med_scan_client.dart';
import '../data/meds_repository.dart';
import '../domain/meds_models.dart';

final medsRepositoryProvider = Provider<MedsRepository>(
  (ref) => SupabaseMedsRepository(ref.watch(supabaseClientProvider)),
);

final medScanClientProvider = Provider<MedScanClient>(
  (ref) => MedScanClient(
    accessToken: () =>
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken,
  ),
);

/// Chọn ảnh đơn thuốc từ camera hoặc thư viện; trả về đường dẫn tệp hoặc null nếu bỏ qua. Ghi đè được khi kiểm thử.
final medPhotoPickerProvider =
    Provider<Future<String?> Function({required bool camera})>(
      (ref) =>
          ({required bool camera}) async => (await ImagePicker().pickImage(
            source: camera ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 2400,
            imageQuality: 90,
          ))?.path,
    );

final medAlarmServiceProvider = Provider<MedAlarmService>(
  (ref) => MedAlarmService(),
);

DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Sắp các lần uống theo giờ tăng dần (không dựa vào thứ tự trả về của máy chủ).
List<Dose> byTime(List<Dose> l) =>
    [...l]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

/// Các lần uống của chính mình: từ đầu hôm nay đến 4 ngày tới.
final myDosesProvider = FutureProvider.autoDispose<List<Dose>>((ref) {
  final me = ref.watch(currentUserProvider.select((u) => u?.id));
  if (me == null) return const <Dose>[];
  final today = startOfDay(DateTime.now());
  return ref
      .watch(medsRepositoryProvider)
      .doses(me, today, today.add(const Duration(days: 5)))
      .then(byTime);
});

final myPlansProvider = FutureProvider.autoDispose<List<MedPlan>>((ref) {
  final me = ref.watch(currentUserProvider.select((u) => u?.id));
  if (me == null) return const <MedPlan>[];
  return ref.watch(medsRepositoryProvider).plans(me);
});

/// Một người thân: 7 ngày qua đến hết ngày mai.
final personDosesProvider = FutureProvider.autoDispose
    .family<List<Dose>, String>((ref, ownerId) {
      final today = startOfDay(DateTime.now());
      return ref
          .watch(medsRepositoryProvider)
          .doses(
            ownerId,
            today.subtract(const Duration(days: 7)),
            today.add(const Duration(days: 2)),
          );
    });

final personPlansProvider = FutureProvider.autoDispose
    .family<List<MedPlan>, String>(
      (ref, ownerId) => ref.watch(medsRepositoryProvider).plans(ownerId),
    );

/// Lần uống kế tiếp của chính mình (chưa uống, chưa quá cửa sổ), hoặc null.
final nextDoseProvider = Provider.autoDispose<Dose?>((ref) {
  final doses = ref.watch(myDosesProvider).value;
  if (doses == null) return null;
  final now = DateTime.now();
  for (final d in doses) {
    final s = d.stateAt(now);
    if (s == DoseState.due || s == DoseState.upcoming) return d;
  }
  return null;
});

/// Giữ báo thức trên máy khớp với lịch trên máy chủ: đặt lại khi lịch đổi, khi mở lại app, và khi đăng nhập.
class MedsSyncHost extends ConsumerStatefulWidget {
  const MedsSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MedsSyncHost> createState() => _MedsSyncHostState();
}

class _MedsSyncHostState extends ConsumerState<MedsSyncHost>
    with WidgetsBindingObserver {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Con có thể đổi lịch lúc app của bác đang mở: làm mới mỗi 5 phút để báo thức luôn khớp lịch.
    _refresh = Timer.periodic(
      const Duration(minutes: 5),
      (_) => ref.invalidate(myDosesProvider),
    );
    final svc = ref.read(medAlarmServiceProvider);
    unawaited(svc.init(onTap: _onTap).then((_) => svc.requestPermissions()));
  }

  void _onTap(String? payload) {
    if (payload == BpReminderService.payload) {
      // Bấm thông báo nhắc đo huyết áp: mở thẳng màn đo.
      BpReminderService.trackOpened();
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) ref.read(routerProvider).go(Routes.measure);
      });
      return;
    }
    if (payload != MedAlarmService.payload) return;
    // Mở màn Thuốc (mục thứ ba của tab Sức khoẻ).
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(healthTabProvider.notifier).set(2);
      ref.read(routerProvider).go(Routes.bp);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(myDosesProvider);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(myDosesProvider, (_, next) {
      final doses = next.value;
      if (doses != null)
        unawaited(ref.read(medAlarmServiceProvider).sync(doses));
    });
    return BpReminderHost(child: widget.child);
  }
}
