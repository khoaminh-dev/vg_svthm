import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/ios_style.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/presentation/providers/chat_controller.dart';
import '../domain/family_models.dart';
import 'family_providers.dart';
import 'widgets/family_widgets.dart';

/// Màn "Gia đình" của người chăm sóc: mỗi người thân một thẻ với đèn trạng thái và huyết áp gần nhất.
class FamilyHomeScreen extends ConsumerWidget {
  const FamilyHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(watchedLinksProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              'Gia đình',
              actions: [
                SoftIconButton(
                  key: const Key('family-add'),
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Theo dõi thêm người thân',
                  filled: true,
                  onPressed: () => context.push(Routes.familyJoin),
                ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(familyLinksProvider);
                  for (final l in links) {
                    ref
                      ..invalidate(personBpProvider(l.otherId))
                      ..invalidate(personRiskProvider(l.otherId));
                  }
                  await ref.read(familyLinksProvider.future);
                },
                child: links.isEmpty
                    ? ListView(
                        key: const Key('family-empty'),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        children: [
                          const SizedBox(height: 48),
                          Icon(
                            Icons.family_restroom_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa theo dõi ai',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nhờ cha mẹ mở Hồ sơ, chọn "Mời người thân theo dõi" để lấy mã, rồi nhập mã đó ở đây.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            key: const Key('family-empty-join'),
                            onPressed: () => context.push(Routes.familyJoin),
                            child: const Text('Nhập mã người thân'),
                          ),
                        ],
                      )
                    : ListView.separated(
                        key: const Key('family-list'),
                        padding: const EdgeInsets.only(top: 4, bottom: 120),
                        itemCount: links.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => PersonCard(link: links[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PersonCard extends ConsumerWidget {
  const PersonCard({super.key, required this.link});

  final FamilyLink link;

  Future<void> _chat(BuildContext context, WidgetRef ref) async {
    final username = link.otherUsername;
    if (username == null) return;
    final room = await ref
        .read(chatControllerProvider.notifier)
        .openDirectRoom(username);
    if (!context.mounted) return;
    if (room == null) {
      final e = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(e!), error: true);
      return;
    }
    context.push(Routes.roomPath(room.id), extra: room);
  }

  Future<void> _nudge(BuildContext context, WidgetRef ref) async {
    Analytics.track('family_nudge');
    try {
      final r = await ref
          .read(familyRepositoryProvider)
          .nudgeMeasure(link.otherId);
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        r == 'ok'
            ? 'Đã nhắc ${link.name} đo huyết áp'
            : 'Vừa nhắc xong, chờ một lúc rồi nhắc lại nhé',
      );
    } catch (e) {
      if (context.mounted)
        showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(personStatusProvider(link.otherId));
    final readings = ref.watch(personBpProvider(link.otherId)).value;
    final latest = (readings == null || readings.isEmpty)
        ? null
        : readings.first;
    final risk = ref.watch(personRiskProvider(link.otherId)).value;

    return FamCard(
      key: Key('person-card-${link.otherId}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Analytics.track('family_open_person');
          context.push(Routes.familyPersonPath(link.otherId));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: link.name,
                  imageUrl: link.otherAvatar,
                  radius: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      status.when(
                        data: (s) => StatusDot(status: s),
                        loading: () =>
                            Text('Đang tải…', style: theme.textTheme.bodySmall),
                        error: (_, _) => Text(
                          'Chưa tải được',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            const SizedBox(height: 12),
            if (latest != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${latest.systolic}/${latest.diastolic}',
                    key: Key('person-bp-${link.otherId}'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: latest.category.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'mmHg · ${timeAgo(latest.measuredAt, DateTime.now())}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              )
            else if (readings != null)
              Text(
                'Chưa đo huyết áp lần nào',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            if (status.value case final s? when s.reasons.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                s.reasons.first,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: lightColor(s.light),
                ),
              ),
            ],
            if (risk != null && risk.level.worthMentioning) ...[
              const SizedBox(height: 4),
              Text(
                'Nguy cơ: ${risk.level.label}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('chat-${link.otherId}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: link.otherUsername == null
                        ? null
                        : () => _chat(context, ref),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 20,
                    ),
                    label: const Text('Nhắn tin'),
                  ),
                ),
                if (link.can(FamilyPerm.health)) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('nudge-${link.otherId}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => _nudge(context, ref),
                      icon: const Icon(Icons.favorite_border_rounded, size: 20),
                      label: const Text('Nhờ đo'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
