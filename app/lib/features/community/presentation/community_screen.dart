import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/presentation/providers/chat_controller.dart';
import 'community_providers.dart';

/// Cộng đồng: danh sách mọi người dùng, bấm "Nhắn tin" để kết bạn và trò chuyện.
/// Chỉ dùng trong đợt thử nghiệm (bật/tắt bằng cờ `community`).
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  Future<void> _chat(BuildContext context, WidgetRef ref, String username) async {
    Analytics.track('community_start_chat');
    final room = await ref.read(chatControllerProvider.notifier).openDirectRoom(username);
    if (!context.mounted) return;
    if (room == null) {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
      return;
    }
    context.push(Routes.roomPath(room.id), extra: room);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(communityUsersProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cộng đồng')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên hoặc @username',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: ref.read(communityQueryProvider.notifier).set,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(communityUsersProvider.future),
              child: users.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      'Chưa tải được danh sách. Kéo xuống để thử lại.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                data: (list) => list.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          Center(
                            child: Text(
                              'Không tìm thấy ai.\nMàn này có thể đã được tắt sau đợt thử nghiệm.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = list[i];
                          return Card(
                            child: ListTile(
                              minTileHeight: 72,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: UserAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 24),
                              title: Text(
                                p.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                              ),
                              subtitle: Text('@${p.username}'),
                              trailing: FilledButton.tonal(
                                onPressed: () => _chat(context, ref, p.username!),
                                child: const Text('Nhắn tin'),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
