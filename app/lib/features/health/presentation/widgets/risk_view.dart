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
import '../../../bp/domain/bp_models.dart';
import '../../domain/health_models.dart';
import '../providers/health_providers.dart';
import '../risk_texts.dart';
import 'risk_charts.dart';

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
    final consent = ref.watch(researchConsentProvider);
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
          const _TrialStrip(),
          if (consent.hasValue && consent.value == null) const _ResearchCard(),
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
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: const Key('open-health-history'),
                  minTileHeight: 64,
                  leading: const Icon(
                    Icons.history_rounded,
                    color: AppColors.navy,
                  ),
                  title: const Text(
                    'Lịch sử hỏi Vy',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                  subtitle: const Text('Những lần bác hỏi Vy về sức khoẻ'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Analytics.track('health_history_open');
                    context.push(Routes.healthHistory);
                  },
                ),
              ),
              if (consent.value != null)
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('research-switch'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: const Icon(
                      Icons.science_outlined,
                      color: AppColors.navy,
                    ),
                    title: const Text(
                      'Tham gia nghiên cứu thử nghiệm',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    subtitle: const Text(
                      'Dùng kết quả và góp ý của bác (không kèm tên)',
                    ),
                    value: consent.value == true,
                    onChanged: (v) {
                      Analytics.track('health_research_toggle', {'on': v});
                      ref.read(researchConsentProvider.notifier).set(v);
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

  /// Chưa có chiều cao/cân nặng và chưa có tiểu đường: mời bổ sung để xem nguy cơ tiểu đường.
  static bool _needsBody(HealthProfile? p) =>
      p != null && !p.hasBody && p.diabetes != true;

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
                child: Text(
                  lv.label,
                  key: const Key('risk-ring'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: lv.color,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                key: const Key('assessment-bp'),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BpBars(
                    category: BpCategory.of(r.systolic, r.diastolic),
                    height: 48,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mức huyết áp (${r.systolic}/${r.diastolic})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        BpCategory.of(r.systolic, r.diastolic).label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: BpCategory.of(r.systolic, r.diastolic).color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (r.strokeP != null || r.heartP != null)
                RiskDonuts(result: r)
              else
                _LevelBar(level: lv),
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (r.diabetesP == null &&
            _needsBody(ref.watch(healthProfileProvider).value)) ...[
          const SizedBox(height: AppSpacing.md),
          _BodyPrompt(onTap: () => context.push(Routes.healthProfile)),
        ],
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'Xu hướng nguy cơ',
          child: Consumer(
            builder: (context, ref, _) {
              final t = ref.watch(riskTrendProvider);
              return t.when(
                loading: () => const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Chưa tải được biểu đồ xu hướng. Kéo xuống để thử lại.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                data: (pts) => RiskTrendChart(points: pts),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'Yếu tố ảnh hưởng',
          footer: r.ageOutOfRange ? ageNote : null,
          child: Wrap(
            key: const Key('risk-factors'),
            spacing: 8,
            runSpacing: 8,
            children: [
              if (r.reasons.isEmpty)
                const _Chip(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Chưa có yếu tố nổi bật',
                  color: AppColors.levelGood,
                ),
              for (final c in r.reasons)
                _Chip(
                  icon: factorChip(c, r).icon,
                  label: factorChip(c, r).label,
                  color: lv.color,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'Bác nên làm',
          child: Row(
            key: const Key('risk-todo'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in todoFor(lv))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(t.icon, color: AppColors.navy, size: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (r.id != null &&
            ref.watch(researchConsentProvider).value == true) ...[
          const SizedBox(height: AppSpacing.md),
          _FeedbackCard(key: ValueKey(r.id), result: r),
        ],
        const SizedBox(height: AppSpacing.md),
        InsetGroup(
          dividerIndent: 0,
          children: [
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

/// Thanh 4 nấc Thấp / Chú ý / Cao / Khẩn; nấc hiện tại đậm và có mũi tên chỉ.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});

  final RiskLevel level;

  static const _short = ['Thấp', 'Chú ý', 'Cao', 'Khẩn'];

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('risk-bar'),
    children: [
      for (final l in RiskLevel.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              children: [
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 28,
                  color: l == level ? l.color : Colors.transparent,
                ),
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: l.color.withValues(alpha: l == level ? 1 : 0.28),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _short[l.index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: l == level ? FontWeight.w700 : FontWeight.w500,
                    color: l == level ? l.color : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.footer});

  final String title;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
          if (footer != null) ...[
            const SizedBox(height: 10),
            Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
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

/// Dòng nhắc luôn hiện ở tab Đánh giá: đây là bản thử nghiệm.
class _TrialStrip extends StatelessWidget {
  const _TrialStrip();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('trial-strip'),
    margin: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.levelWatch.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.science_outlined, size: 20, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Bản thử nghiệm: kết quả chỉ để tham khảo, không thay thế bác sĩ.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Hỏi một lần: có đồng ý dùng kết quả và góp ý cho nghiên cứu không. Rút lại được bằng công tắc bên dưới.
class _ResearchCard extends ConsumerWidget {
  const _ResearchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void answer(bool v) {
      Analytics.track('health_research_answer', {'on': v});
      ref.read(researchConsentProvider.notifier).set(v);
    }

    return Container(
      key: const Key('research-card'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giúp Viegrand cải thiện?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Công cụ này đang được thử nghiệm. Bác có đồng ý cho Viegrand dùng kết quả đánh giá và góp ý của bác, không kèm tên, để kiểm tra và cải thiện công cụ không? Bác có thể rút lại bất cứ lúc nào.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('research-yes'),
                  onPressed: () => answer(true),
                  child: const Text('Đồng ý'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('research-no'),
                  onPressed: () => answer(false),
                  child: const Text('Không, cảm ơn'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Kết quả này có đúng với bác không?" Một chạm là lưu. Chọn "Chưa đúng" thì có ô ghi chú tuỳ chọn.
class _FeedbackCard extends ConsumerStatefulWidget {
  const _FeedbackCard({super.key, required this.result});

  final RiskResult result;

  @override
  ConsumerState<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends ConsumerState<_FeedbackCard> {
  String? _verdict;
  final _note = TextEditingController();
  bool _saving = false;
  bool _failed = false;
  bool _noteSent = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String verdict, {bool withNote = false}) async {
    final id = widget.result.id;
    if (id == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
      _verdict = verdict;
    });
    try {
      await ref
          .read(healthRepositoryProvider)
          .saveFeedback(
            id,
            verdict: verdict,
            level: widget.result.level.code,
            note: verdict == 'wrong' ? _note.text : null,
          );
      Analytics.track('health_feedback', {'verdict': verdict});
      ref.invalidate(riskFeedbackProvider(id));
      if (mounted) setState(() => _noteSent = withNote);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.result.id!;
    final saved = ref.watch(riskFeedbackProvider(id)).value;
    final verdict = _verdict ?? saved?.verdict;
    if (_verdict == null && saved?.note != null && _note.text.isEmpty) {
      _note.text = saved!.note!;
    }

    Widget choice(String v, String label, IconData icon) {
      final on = verdict == v && !_failed;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            key: Key('fb-$v'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: on
                  ? AppColors.navy.withValues(alpha: 0.1)
                  : null,
              side: BorderSide(
                color: on ? AppColors.navy : AppColors.border,
                width: on ? 2 : 1,
              ),
            ),
            onPressed: _saving ? null : () => _save(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('feedback-card'),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kết quả này có đúng với bác không?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              choice('right', 'Đúng', Icons.check_circle_outline_rounded),
              choice('wrong', 'Chưa đúng', Icons.highlight_off_rounded),
              choice('unsure', 'Không rõ', Icons.help_outline_rounded),
            ],
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              'Chưa gửi được, bác thử lại nhé.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.levelDanger,
              ),
            ),
          ] else if (verdict != null) ...[
            const SizedBox(height: 8),
            Text(
              'Cảm ơn bác đã góp ý. Bác bấm lại để đổi.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (verdict == 'wrong') ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('fb-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Bác thấy chưa đúng ở đâu? (không bắt buộc)',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('fb-note-send'),
                onPressed: _saving
                    ? null
                    : () => _save('wrong', withNote: true),
                child: Text(_noteSent ? 'Đã gửi' : 'Gửi ghi chú'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mời bổ sung chiều cao và cân nặng để có thêm vòng tròn nguy cơ tiểu đường.
class _BodyPrompt extends StatelessWidget {
  const _BodyPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Material(
      color: AppColors.navy.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('body-prompt'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.monitor_weight_outlined, color: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Thêm chiều cao và cân nặng để xem nguy cơ tiểu đường',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}
