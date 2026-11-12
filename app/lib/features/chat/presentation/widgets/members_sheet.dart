import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';
import 'text_prompt_dialog.dart';

/// Danh sách thành viên của phòng, kèm trạng thái online và nút mời thêm người.
class MembersSheet extends ConsumerWidget {
  const MembersSheet({super.key, required this.roomId});

  final String roomId;

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final username = await showTextPromptDialog(
      context,
      title: 'Thêm thành viên',
      label: 'Tên người dùng',
      prefix: '@',
      confirmLabel: 'Thêm',
      validator: Validators.username,
    );
    if (username == null || !context.mounted) return;

    final ok = await ref.read(chatControllerProvider.notifier).addMember(roomId, username);
    if (!context.mounted) return;
    if (ok) {
      showAppSnackBar(context, 'Đã thêm @$username vào phòng');
    } else {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(roomId));
    final online = ref.watch(onlineProvider(roomId)).value ?? const <String>{};

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Thành viên'),
            trailing: TextButton.icon(
              onPressed: () => _invite(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Thêm'),
            ),
          ),
          Flexible(
            child: members.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(errorMessage(e)),
              ),
              data: (list) => ListView(
                shrinkWrap: true,
                children: [
                  for (final p in list)
                    ListTile(
                      leading: UserAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 18),
                      title: Text(p.name),
                      subtitle: p.username == null ? null : Text('@${p.username}'),
                      trailing: Icon(
                        Icons.circle,
                        size: 10,
                        color: online.contains(p.id) ? Colors.green : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
