import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ios_style.dart';
import '../../../bp/presentation/providers/bp_providers.dart';
import '../../domain/health_models.dart';
import '../providers/health_providers.dart';
import '../risk_texts.dart';

Future<void> callEmergency() => launchUrl(Uri.parse('tel:115'));

/// Tab "Đánh giá": chỉ đọc kết quả. Đánh giá tự chạy sau mỗi lần đo; mở tab này cũng làm mới ngầm
/// (server trả lại kết quả cũ nếu chưa có gì thay đổi nên không tốn thêm).
class RiskView extends ConsumerStatefulWidget {
  const RiskView({super.key});

  @override
  ConsumerState<RiskView> createState() => _RiskViewState();
}

class _RiskViewState extends ConsumerState<RiskView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(riskRunnerProvider.notifier).run();
    });
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final risk = ref.watch(latestRiskProvider);
    final run = ref.watch(riskRunnerProvider);
    final readings = ref.watch(bpReadingsProvider).value;
    final r = risk.value;

    Widget body;
    if (r == null) {
      final noReading = readings != null && readings.isEmpty;
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 10),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              noReading
                  ? 'Chụp huyết áp để nhận đánh giá đầu tiên.'
                  : (run.isLoading || risk.isLoading
                        ? 'Đang đánh giá…'
                        : 'Chưa có đánh giá.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (noReading) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => context.push(Routes.measure),
                child: const Text('Đo huyết áp'),
              ),
            ],
          ],
        ),
      );
    } else {
      body = _result(context, theme, r);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(riskRunnerProvider.notifier).run(),
      child: ListView(
        key: const Key('risk-view'),
        padding: const EdgeInsets.only(top: 4, bottom: 120),
        children: [
          body,
          if (run.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                'Chưa cập nhật được đánh giá mới. Kéo xuống để thử lại.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          InsetGroup(
            dividerIndent: 0,
            children: [
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: const Key('open-health-profile'),
                  minTileHeight: 64,
                  leading: const Icon(
                    Icons.assignment_ind_outlined,
                    color: AppColors.navy,
                  ),
                  title: const Text(
                    'Hồ sơ sức khoẻ',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                  subtitle: const Text('Sửa khi có gì thay đổi'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Analytics.track('health_profile_open');
                    context.push(Routes.healthProfile);
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              disclaimer,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, ThemeData theme, RiskResult r) {
    final lv = r.level;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            children: [
              Semantics(
                label: 'Mức nguy cơ: ${lv.label}',
                excludeSemantics: true,
                child: Container(
                  key: const Key('risk-ring'),
                  width: 148,
                  height: 148,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: lv.color, width: 12),
                  ),
                  child: Text(
                    lv.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: lv.color,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                riskSentence(lv),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Dựa trên huyết áp ${r.systolic}/${r.diastolic} lúc ${_fmt(r.measuredAt)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              if (lv == RiskLevel.urgent) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton.icon(
                    key: const Key('call-115'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.levelDanger,
                    ),
                    onPressed: callEmergency,
                    icon: const Icon(Icons.phone_rounded),
                    label: const Text(
                      'Gọi 115',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InsetGroup(
          dividerIndent: 0,
          children: [
            _Fold(
              title: 'Vì sao có kết quả này',
              children: [
                if (r.reasons.isEmpty)
                  const Text('Chưa có yếu tố nguy cơ nào nổi bật.'),
                for (final c in r.reasons) _Bullet(reasonText(c, r)),
                if (r.ageOutOfRange) const _Bullet(ageNote),
              ],
            ),
            _Fold(
              title: 'Bác có thể làm gì',
              children: [for (final t in adviceFor(lv)) _Bullet(t)],
            ),
            _Fold(
              title: 'Khi nào cần đi khám ngay',
              children: [
                const Text(
                  'Nếu bác có một trong các dấu hiệu sau, gọi 115 hoặc đến cơ sở y tế ngay:',
                ),
                const SizedBox(height: 6),
                for (final t in redFlags) _Bullet(t),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Fold extends StatelessWidget {
  const _Fold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      children: children,
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, right: 10),
          child: Icon(Icons.circle, size: 6),
        ),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
}
