import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/health_repository.dart';
import '../../domain/health_models.dart';

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => SupabaseHealthRepository(ref.watch(supabaseClientProvider)),
);

/// Hồ sơ sức khoẻ của người dùng hiện tại. `data(null)` nghĩa là đã tải xong và chưa nhập
/// (router dựa vào đó để bắt nhập). Đổi tài khoản thì tải lại.
class HealthProfileNotifier extends AsyncNotifier<HealthProfile?> {
  @override
  Future<HealthProfile?> build() async {
    final uid = ref.watch(currentUserProvider.select((u) => u?.id));
    if (uid == null) return null;
    return ref.read(healthRepositoryProvider).getProfile();
  }

  Future<void> save(HealthProfile profile) async {
    await ref.read(healthRepositoryProvider).saveProfile(profile);
    state = AsyncData(profile);
    // Hồ sơ đổi thì kết quả cũ không còn đúng: tính lại ngầm.
    ref.read(riskRunnerProvider.notifier).run();
  }
}

final healthProfileProvider =
    AsyncNotifierProvider<HealthProfileNotifier, HealthProfile?>(
      HealthProfileNotifier.new,
    );

/// Lần đánh giá gần nhất đã lưu (Trang chủ và tab Đánh giá đọc từ đây).
final latestRiskProvider = FutureProvider.autoDispose<RiskResult?>(
  (ref) => ref.watch(healthRepositoryProvider).latestAssessment(),
);

/// Chạy đánh giá trên server. Gọi tự động sau mỗi lần đo huyết áp và khi sửa hồ sơ.
class RiskRunner extends Notifier<AsyncValue<RiskResult?>> {
  @override
  AsyncValue<RiskResult?> build() => const AsyncData(null);

  void clear() => state = const AsyncData(null);

  Future<void> run() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      final r = await ref.read(healthRepositoryProvider).runAssessment();
      state = AsyncData(r);
      if (r != null) ref.invalidate(latestRiskProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final riskRunnerProvider =
    NotifierProvider<RiskRunner, AsyncValue<RiskResult?>>(RiskRunner.new);

/// Mục đang chọn ở tab Sức khoẻ: 0 = Huyết áp, 1 = Đánh giá.
class HealthTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int i) => state = i;
}

final healthTabProvider = NotifierProvider<HealthTabNotifier, int>(
  HealthTabNotifier.new,
);
