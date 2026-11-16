import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../health/domain/health_models.dart';
import '../../health/presentation/providers/health_providers.dart';
import '../data/family_repository.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../safety/domain/safety_models.dart';
import '../../safety/presentation/safety_providers.dart';
import '../domain/alerts_feed.dart';
import '../domain/family_models.dart';
import '../domain/family_status.dart';

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => SupabaseFamilyRepository(ref.watch(supabaseClientProvider)),
);

/// Mọi liên kết gia đình của tôi (cả hai chiều). Làm mới khi mở lại màn hoặc gọi `invalidate`.
final familyLinksProvider = FutureProvider<List<FamilyLink>>((ref) {
  if (ref.watch(currentUserProvider.select((u) => u?.id)) == null)
    return const <FamilyLink>[];
  return ref.watch(familyRepositoryProvider).myFamily();
});

/// Những người tôi đang theo dõi (tôi là người chăm sóc), còn hoạt động.
final watchedLinksProvider = Provider.autoDispose<List<FamilyLink>>((ref) {
  final all = ref.watch(familyLinksProvider).value ?? const <FamilyLink>[];
  return [
    for (final l in all)
      if (!l.iAmOwner && l.active) l,
  ];
});

/// Những người đang theo dõi tôi (tôi là người được chăm sóc).
final watchersProvider = Provider.autoDispose<List<FamilyLink>>((ref) {
  final all = ref.watch(familyLinksProvider).value ?? const <FamilyLink>[];
  return [
    for (final l in all)
      if (l.iAmOwner) l,
  ];
});

/// Lựa chọn "Chế độ theo dõi người thân" (nhớ theo từng tài khoản trên máy này).
class WatchModeNotifier extends Notifier<bool> {
  String? _uid;

  @override
  bool build() {
    _uid = ref.watch(currentUserProvider.select((u) => u?.id));
    // Đã có vai trò thì vai trò quyết định (người thân luôn ở chế độ theo dõi).
    final role = ref.watch(currentUserProvider.select((u) => u?.role));
    if (role != null) return role == AppRole.family;
    if (_uid != null) _load(_uid!);
    return false;
  }

  Future<void> _load(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_uid == uid && p.getBool('watch_mode_$uid') == true) state = true;
    } catch (_) {}
  }

  Future<void> set(bool on) async {
    state = on;
    final uid = _uid;
    if (uid == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('watch_mode_$uid', on);
    } catch (_) {}
  }
}

final watchModeProvider = NotifierProvider<WatchModeNotifier, bool>(
  WatchModeNotifier.new,
);

/// Đang ở chế độ theo dõi thật sự: đã chọn và còn theo dõi ít nhất một người.
final effectiveWatchModeProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(watchModeProvider) &&
      ref.watch(watchedLinksProvider).isNotEmpty;
});

// ---------- Dữ liệu của một người thân (theo id chủ dữ liệu) ----------

final personBpProvider = FutureProvider.autoDispose
    .family<List<BpReading>, String>(
      (ref, ownerId) =>
          ref.watch(bpRepositoryProvider).list(limit: 60, ownerId: ownerId),
    );

final personRiskProvider = FutureProvider.autoDispose
    .family<RiskResult?, String>(
      (ref, ownerId) => ref
          .watch(healthRepositoryProvider)
          .latestAssessment(ownerId: ownerId),
    );

final personTrendProvider = FutureProvider.autoDispose
    .family<List<TrendPoint>, String>(
      (ref, ownerId) =>
          ref.watch(healthRepositoryProvider).trend(ownerId: ownerId),
    );

final personProfileProvider = FutureProvider.autoDispose
    .family<HealthProfile?, String>(
      (ref, ownerId) =>
          ref.watch(healthRepositoryProvider).getProfile(ownerId: ownerId),
    );

/// Đèn trạng thái của một người thân, tính từ số đo và đánh giá mới nhất.
final personStatusProvider = Provider.autoDispose
    .family<AsyncValue<FamilyStatus>, String>((ref, ownerId) {
      final bp = ref.watch(personBpProvider(ownerId));
      final risk = ref.watch(personRiskProvider(ownerId));
      if (bp.hasError)
        return AsyncError(bp.error!, bp.stackTrace ?? StackTrace.current);
      if (!bp.hasValue) return const AsyncLoading();
      return AsyncData(
        computeFamilyStatus(
          readings: bp.value!,
          risk: risk.value,
          now: DateTime.now(),
        ),
      );
    });

/// Cảnh báo gần đây của những người tôi theo dõi (7 ngày), tổng hợp từ huyết áp, thuốc và SOS.
final alertsFeedProvider = FutureProvider.autoDispose<List<AlertItem>>((ref) async {
  final links = ref.watch(watchedLinksProvider);
  if (links.isEmpty) return const <AlertItem>[];
  final bp = <String, List<BpReading>>{};
  final doses = <String, List<Dose>>{};
  await Future.wait([
    for (final l in links) ...[
      if (l.can(FamilyPerm.health))
        ref.watch(personBpProvider(l.otherId).future).then((v) => bp[l.otherId] = v).catchError((_) => <BpReading>[]),
      if (l.can(FamilyPerm.medsView))
        ref.watch(personDosesProvider(l.otherId).future).then((v) => doses[l.otherId] = v).catchError((_) => <Dose>[]),
    ],
  ]);
  var sos = <SosEvent>[];
  try {
    sos = await ref.watch(safetyRepositoryProvider).recentSos();
  } catch (_) {}
  return buildAlerts(links: links, bp: bp, doses: doses, sos: sos, now: DateTime.now());
});
