import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/honorific.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../../../shared/widgets/ios_components.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../voice/core/vy_core.dart';
import '../data/plan_repository.dart';
import '../domain/plan_models.dart';
import '../../../core/router/safe_pop.dart';

/// Gói Vy Live: xem gói đang bán, đặt gói, theo dõi đơn chờ admin xác nhận thanh toán, và xem gói đang dùng.
/// Thanh toán làm ngoài app; chỉ khi admin xác nhận thì Vy Live mới bật (cho cả người thân đang liên kết).
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  Future<void> _order(BuildContext context, WidgetRef ref, PlanOption p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gửi yêu cầu ${p.name}?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        content: Text(
          '${formatVnd(p.priceVnd)} cho ${p.days} ngày. Yêu cầu của bạn sẽ được gửi cho Viegrand. Vy Live bật sau khi Viegrand duyệt.',
          style: const TextStyle(fontSize: 18),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(key: const Key('plan-cancel'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Thôi', style: TextStyle(fontSize: 18))),
          FilledButton(
            key: const Key('plan-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(130, 52)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi yêu cầu', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Analytics.track('plan_order', {'days': p.days});
    try {
      await ref.read(planRepositoryProvider).request(p.id);
      ref.invalidate(planOverviewProvider);
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(planRepositoryProvider).cancelPending();
      ref.invalidate(planOverviewProvider);
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(planOverviewProvider);
    final theme = Theme.of(context);
    // Vừa được bật gói: bỏ lệnh chặn Vy Live (máy chủ từng từ chối) để dùng được ngay.
    ref.listen(planOverviewProvider, (_, next) {
      if (next.value?.live == true) ref.read(vyCoreProvider.notifier).resetLiveBlock();
    });
    final elder = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;

    Widget body(PlanOverview o) {
      final now = DateTime.now();
      final mine = o.mine;
      final mineLive = mine != null && mine.isLiveAt(now);
      return ListView(
        key: const Key('plan-view'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 120),
        children: [
          _StatusCard(overview: o, now: now, elder: elder),
          const SizedBox(height: AppSpacing.md),
          if (!o.live && !(mine != null && mine.isPending)) ...[
            const _Benefits(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (mine != null && mine.isPending) ...[
            _PendingCard(order: mine, payNote: o.payNote, onCancel: () => _cancel(context, ref)),
          ] else ...[
            Text(
              mineLive ? 'Gia hạn thêm' : 'Chọn gói',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: AppSpacing.sm),
            if (o.plans.isEmpty)
              Container(
                key: const Key('plan-none'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text('Hiện chưa có gói nào đang bán. Bạn quay lại sau nhé.', style: theme.textTheme.bodyLarge),
              )
            else
              for (final p in o.plans) _PlanCard(plan: p, onTap: () => _order(context, ref, p)),
          ],
        ],
      );
    }

    return Scaffold(
      bottomNavigationBar: elder ? ElderBackBar(onPressed: () => safePop(context)) : null,
      appBar: AppBar(
        title: const Text('Gói Vy Live'),
        leading: SoftBackLeading(onPressed: () => safePop(context)),
      ),
      body: SafeArea(
        child: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(errorMessage(e), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('plan-retry'),
                    onPressed: () => ref.invalidate(planOverviewProvider),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
          data: (o) => RefreshIndicator(onRefresh: () async => ref.refresh(planOverviewProvider.future), child: body(o)),
        ),
      ),
    );
  }
}

/// Trạng thái hiện tại: đang bật (và đến khi nào), do người thân đăng ký, chờ xác nhận, hay chưa có.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.overview, required this.now, required this.elder});

  final PlanOverview overview;
  final DateTime now;
  final bool elder;

  @override
  Widget build(BuildContext context) {
    final mine = overview.mine;
    final until = mine != null && mine.isLiveAt(now) ? mine.expiresAt : null;
    final (IconData icon, Color color, String title, String sub) = overview.live
        ? (
            Icons.verified_rounded,
            const Color(0xFF2E9E5B),
            'Vy Live đang bật',
            until != null
                ? 'Đến hết ngày ${formatDay(until)}.'
                : 'Do ${overview.coveredBy ?? 'người thân'} đăng ký cho bạn.',
          )
        : mine != null && mine.isPending
            ? (Icons.hourglass_top_rounded, const Color(0xFFD08A1E), 'Đang chờ duyệt', 'Yêu cầu của bạn đang chờ Viegrand duyệt.')
            : (Icons.lock_outline_rounded, AppColors.textMuted, 'Chưa bật Vy Live', elder ? hon('Chưa có gói. Bác có thể nhờ người thân đăng ký giúp.') : 'Chưa có gói. Chọn một gói bên dưới để bật Vy Live cho bạn và người thân.');
    return Container(
      key: const Key('plan-status'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 14, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navyDeep)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lợi ích của gói, ba dòng icon thay cho đoạn văn: nhìn là hiểu.
class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: Color(0xFFEAF0FF), shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: AppColors.navyDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.navyDeep)),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('plan-benefits'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 14, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          row(Icons.record_voice_over_rounded, 'Nói chuyện với Vy tự nhiên như người thật'),
          row(Icons.groups_2_rounded, 'Một gói dùng chung cho cả người thân'),
          row(Icons.shield_outlined, 'SOS và nhắc thuốc luôn miễn phí'),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});

  final PlanOption plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        elevation: 1.5,
        shadowColor: AppColors.cardShadow,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: Key('plan-${plan.id}'),
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.navyDeep)),
                      Text('${plan.days} ngày${plan.note.isEmpty ? '' : ' · ${plan.note}'}', style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatVnd(plan.priceVnd), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navyDeep)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yêu cầu đang chờ duyệt: mã to, gói, số tiền, ghi chú của Viegrand, nút huỷ.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.order, required this.payNote, required this.onCancel});

  final PlanOrder order;
  final String payNote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('plan-pending'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Yêu cầu của bạn', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${order.planName} · ${order.days} ngày · ${formatVnd(order.priceVnd)}', style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 10),
          const Text('Mã yêu cầu', style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  order.code,
                  key: const Key('plan-code'),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.navyDeep),
                ),
              ),
              IconButton(
                key: const Key('plan-copy'),
                tooltip: 'Chép mã yêu cầu',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: order.code));
                  if (context.mounted) showAppSnackBar(context, 'Đã chép mã yêu cầu');
                },
              ),
            ],
          ),
          if (payNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(payNote, style: const TextStyle(fontSize: 17, height: 1.35)),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('plan-cancel-order'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: onCancel,
            child: const Text('Huỷ yêu cầu này', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}
