import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/plan_models.dart';

/// Gói Vy Live. Mọi thay đổi đi qua các hàm của máy chủ (RPC); admin xác nhận thanh toán nên app không tự bật gói.
abstract interface class PlanRepository {
  Future<PlanOverview> overview();

  /// Đặt gói [planId]. Nếu đã có một đơn chờ thì trả về đơn đó (không tạo thêm).
  Future<PlanOrder> request(String planId);

  /// Huỷ đơn đang chờ của mình.
  Future<void> cancelPending();
}

class SupabasePlanRepository implements PlanRepository {
  SupabasePlanRepository(this._client);

  final SupabaseClient _client;

  AppFailure _fail(PostgrestException e) {
    final m = e.message;
    if (m.contains('plan_unavailable')) return const AppFailure('Gói này hiện không còn bán. Hãy chọn gói khác.');
    if (m.contains('too_many_orders')) return const AppFailure('Hôm nay đã đặt quá nhiều đơn. Hãy thử lại vào ngày mai.');
    return AppFailure('Chưa xử lý được ($m)');
  }

  @override
  Future<PlanOverview> overview() async {
    try {
      final r = await _client.rpc('plan_overview');
      return PlanOverview.fromJson(Map<String, dynamic>.from(r as Map));
    } on PostgrestException catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<PlanOrder> request(String planId) async {
    try {
      final r = await _client.rpc('request_subscription', params: {'p_plan': planId});
      return PlanOrder.fromJson(Map<String, dynamic>.from(r as Map));
    } on PostgrestException catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<void> cancelPending() async {
    try {
      await _client.rpc('cancel_my_pending_subscription');
    } on PostgrestException catch (e) {
      throw _fail(e);
    }
  }
}

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => SupabasePlanRepository(ref.watch(supabaseClientProvider)),
);

/// Gói của mình (tải lại bằng `ref.invalidate`).
final planOverviewProvider = FutureProvider.autoDispose<PlanOverview>(
  (ref) => ref.watch(planRepositoryProvider).overview(),
);
