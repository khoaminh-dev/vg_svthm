import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_style.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../health/data/advice_speaker.dart';
import '../../family/presentation/family_providers.dart';
import '../../bp/data/bp_reminder_service.dart';
import '../../bp/presentation/providers/bp_reminder_providers.dart';
import '../../push/push_service.dart';

/// Tab Hồ sơ: thông tin tài khoản, phiên bản app và đăng xuất.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất khỏi Viegrand?'),
        content: const Text('Bạn cần đăng nhập lại để dùng tiếp.'),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.levelDanger,
              minimumSize: const Size(140, AppSpacing.tapTarget),
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Analytics.track('tap_sign_out');
    await ref.read(pushServiceProvider).unregister();
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget row(IconData icon, String label, String value) => ListTile(
      minTileHeight: 64,
      leading: Icon(icon, color: scheme.primary),
      title: Text(
        label,
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      subtitle: Text(value, style: text.titleMedium),
    );

    final speakTile = SwitchListTile(
      key: const Key('profile-speak'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      secondary: Icon(
        Icons.volume_up_outlined,
        color: scheme.primary,
      ),
      title: const Text(
        'Đọc lời khuyên sau khi đo',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      subtitle: Text(user?.role == AppRole.family ? 'Máy tự đọc to cho bạn nghe' : 'Máy tự đọc to cho bác nghe'),
      value: ref.watch(speakAdviceProvider).value ?? true,
      onChanged: (v) {
        Analytics.track('speak_advice_toggle', {'on': v});
        ref.read(speakAdviceProvider.notifier).set(v);
      },
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                LargeTitle(user?.role == AppRole.family ? 'Tôi' : 'Hồ sơ'),
                if (user != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: UserAvatar(
                      name: user.displayName,
                      imageUrl: user.avatarUrl,
                      radius: 52,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    user.displayName,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (user.role != AppRole.elder)
                  InsetGroup(
                    dividerIndent: 56,
                    children: [
                      if (user.username != null)
                        row(
                          Icons.alternate_email_rounded,
                          'Tên người dùng',
                          user.username!,
                        ),
                      if (user.email != null)
                        row(Icons.mail_outline_rounded, 'Email', user.email!),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (user?.role != AppRole.elder)
                InsetGroup(
                  dividerIndent: 0,
                  children: [
                    if (user?.role != AppRole.elder)
                    Semantics(
                      button: true,
                      label: 'Hồ sơ sức khoẻ',
                      excludeSemantics: true,
                      child: ListTile(
                        key: const Key('profile-health'),
                        minTileHeight: 64,
                        leading: Icon(
                          Icons.assignment_ind_outlined,
                          color: scheme.primary,
                        ),
                        title: const Text(
                          'Hồ sơ sức khoẻ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(Routes.healthProfile),
                      ),
                    ),
                    speakTile,
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (user?.role == AppRole.elder) ...[
                  // Người cao tuổi: chỉ ba việc hay dùng, mỗi việc một ô to. Cài đặt còn lại gom vào "Cài đặt khác".
                  _ElderProfileShortcuts(me: user!.id),
                  const SizedBox(height: AppSpacing.md),
                  const _BpReminderSettings(elder: true),
                  const SizedBox(height: AppSpacing.md),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const Key('profile-more'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                      title: const Text(
                        'Cài đặt khác',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      children: [
                        speakTile,
                        const SizedBox(height: AppSpacing.md),
                        const _FamilySettings(),
                        const SizedBox(height: AppSpacing.md),
                        const _NotificationSettings(),
                      ],
                    ),
                  ),
                ] else ...[
                  const _BpReminderSettings(elder: false),
                  const SizedBox(height: AppSpacing.lg),
                  const _FamilySettings(),
                  const SizedBox(height: AppSpacing.lg),
                  const _NotificationSettings(),
                ],
                const SizedBox(height: AppSpacing.lg),
                InsetGroup(
                  dividerIndent: 0,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Đăng xuất',
                      excludeSemantics: true,
                      child: ListTile(
                        minTileHeight: 60,
                        onTap: () => _confirmSignOut(context, ref),
                        title: const Text(
                          'Đăng xuất',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.levelDanger,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final i = snap.data;
                    return Text(
                      i == null
                          ? ''
                          : 'Viegrand ${i.version} (${i.buildNumber})',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ba việc người cao tuổi hay làm ở Hồ sơ, mỗi việc một ô lớn có biểu tượng và một dòng chữ.
class _ElderProfileShortcuts extends ConsumerWidget {
  const _ElderProfileShortcuts({required this.me});

  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchers = ref.watch(watchersProvider);
    Widget big(String key, IconData icon, String title, String sub, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 40, color: AppColors.navy),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(sub, style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      key: const Key('profile-elder-shortcuts'),
      children: [
        big(
          'profile-invite',
          Icons.family_restroom_outlined,
          'Mời người thân',
          watchers.isEmpty ? 'Để con xem được sức khoẻ của bác' : '${watchers.length} người đang theo dõi',
          () => context.push(Routes.familyInvite),
        ),
        big(
          'profile-emergency-card',
          Icons.medical_information_outlined,
          'Thẻ y tế khẩn cấp',
          'Nhóm máu, dị ứng, số người nhà',
          () => context.push(Routes.emergencyCardFor(me)),
        ),
        big(
          'profile-health',
          Icons.assignment_ind_outlined,
          'Hồ sơ sức khoẻ',
          'Tuổi, bệnh nền, chiều cao, cân nặng',
          () => context.push(Routes.healthProfile),
        ),
        big(
          'profile-role',
          Icons.swap_horiz_rounded,
          'Đổi vai trò',
          'Đang là: ${ref.watch(currentUserProvider)?.role?.label ?? 'chưa chọn'}',
          () => context.push(Routes.chooseRoleChange),
        ),
      ],
    );
  }
}

/// Mục "Nhắc đo huyết áp": bật/tắt, giờ buổi sáng, giờ buổi tối (tuỳ chọn). Người cao tuổi: mặc định bật, chữ to.
class _BpReminderSettings extends ConsumerWidget {
  const _BpReminderSettings({required this.elder});

  final bool elder;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<String?> _pick(BuildContext context, String help, String initial) async {
    final p = initial.split(':');
    final t = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: w!,
      ),
    );
    return t == null ? null : _fmt(t);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(bpReminderSettingsProvider).value ?? const BpReminderSettings();
    final n = ref.read(bpReminderSettingsProvider.notifier);
    final on = s.effectiveEnabled(elder: elder);
    final titleStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: elder ? 20 : 17);
    final subStyle = TextStyle(fontSize: elder ? 17 : 14);
    const pad = EdgeInsets.symmetric(horizontal: 16);
    return InsetGroup(
      key: const Key('bp-reminder-settings'),
      dividerIndent: 0,
      children: [
        SwitchListTile(
          key: const Key('bp-reminder-toggle'),
          contentPadding: pad,
          secondary: Icon(Icons.alarm_on_rounded, color: scheme.primary, size: elder ? 36 : 24),
          title: Text('Nhắc đo huyết áp', style: titleStyle),
          subtitle: Text(
            on ? 'Mỗi ngày nhắc một lần, hôm nào đo rồi thì thôi' : 'Đang tắt',
            style: subStyle,
          ),
          value: on,
          onChanged: (v) {
            Analytics.track('bp_reminder_toggle', {'on': v});
            n.setEnabled(v);
          },
        ),
        if (on) ...[
          ListTile(
            key: const Key('bp-reminder-morning'),
            contentPadding: pad,
            minTileHeight: elder ? 72 : 60,
            leading: Icon(Icons.wb_sunny_outlined, color: scheme.primary, size: elder ? 36 : 24),
            title: Text('Buổi sáng', style: titleStyle),
            subtitle: Text('Chạm để đổi giờ', style: subStyle),
            trailing: Text(
              s.morning,
              style: TextStyle(fontSize: elder ? 28 : 20, fontWeight: FontWeight.w800),
            ),
            onTap: () async {
              final v = await _pick(context, 'Nhắc đo buổi sáng lúc', s.morning);
              if (v == null) return;
              Analytics.track('bp_reminder_time_set', {'slot': 'morning'});
              n.setMorning(v);
            },
          ),
          ListTile(
            key: const Key('bp-reminder-evening'),
            contentPadding: pad,
            minTileHeight: elder ? 72 : 60,
            leading: Icon(Icons.nights_stay_outlined, color: scheme.primary, size: elder ? 36 : 24),
            title: Text('Buổi tối', style: titleStyle),
            subtitle: Text(
              s.evening == null ? 'Chưa đặt. Chạm để thêm một giờ buổi tối' : 'Chạm để đổi giờ',
              style: subStyle,
            ),
            trailing: s.evening == null
                ? const Icon(Icons.add_circle_outline_rounded, size: 30)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.evening!,
                        style: TextStyle(fontSize: elder ? 28 : 20, fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        key: const Key('bp-reminder-evening-remove'),
                        tooltip: 'Bỏ nhắc buổi tối',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          Analytics.track('bp_reminder_time_set', {'slot': 'evening_off'});
                          n.setEvening(null);
                        },
                      ),
                    ],
                  ),
            onTap: () async {
              final v = await _pick(context, 'Nhắc đo buổi tối lúc', s.evening ?? '19:00');
              if (v == null) return;
              Analytics.track('bp_reminder_time_set', {'slot': 'evening'});
              n.setEvening(v);
            },
          ),
        ],
      ],
    );
  }
}

/// Mục "Thông báo": bật/tắt thông báo tin nhắn, thông báo bản cập nhật, và việc hiện nội dung tin trên màn hình khoá.
class _NotificationSettings extends ConsumerWidget {
  const _NotificationSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(pushPrefsProvider).value ?? const PushPrefs();
    final notifier = ref.read(pushPrefsProvider.notifier);
    const pad = EdgeInsets.symmetric(horizontal: 16);
    const titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 17);
    return InsetGroup(
      key: const Key('notification-settings'),
      dividerIndent: 0,
      children: [
        SwitchListTile(
          key: const Key('push-messages'),
          contentPadding: pad,
          secondary: Icon(Icons.notifications_outlined, color: scheme.primary),
          title: const Text('Thông báo tin nhắn', style: titleStyle),
          subtitle: Text(ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.family ? 'Báo khi có người nhắn cho bạn' : 'Báo khi có người nhắn cho bác'),
          value: prefs.messages,
          onChanged: (v) {
            Analytics.track('push_toggle', {'kind': 'messages', 'on': v});
            notifier.save(prefs.copyWith(messages: v));
          },
        ),
        SwitchListTile(
          key: const Key('push-show-text'),
          contentPadding: pad,
          secondary: Icon(Icons.visibility_outlined, color: scheme.primary),
          title: const Text('Hiện nội dung tin nhắn', style: titleStyle),
          subtitle: const Text('Tắt thì chỉ hiện tên người nhắn'),
          value: prefs.showText,
          onChanged: prefs.messages
              ? (v) {
                  Analytics.track('push_toggle', {
                    'kind': 'show_text',
                    'on': v,
                  });
                  notifier.save(prefs.copyWith(showText: v));
                }
              : null,
        ),
        SwitchListTile(
          key: const Key('push-updates'),
          contentPadding: pad,
          secondary: Icon(Icons.system_update_outlined, color: scheme.primary),
          title: const Text('Thông báo bản cập nhật', style: titleStyle),
          subtitle: const Text('Báo khi Viegrand có bản mới'),
          value: prefs.updates,
          onChanged: (v) {
            Analytics.track('push_toggle', {'kind': 'updates', 'on': v});
            notifier.save(prefs.copyWith(updates: v));
          },
        ),
        if (ref.watch(watchedLinksProvider).isNotEmpty) ...[
          SwitchListTile(
            key: const Key('push-dose-alerts'),
            contentPadding: pad,
            secondary: Icon(Icons.medication_outlined, color: scheme.primary),
            title: const Text('Báo khi người thân quên thuốc', style: titleStyle),
            subtitle: const Text('Cũng báo khi sắp hết thuốc, sắp tái khám'),
            value: prefs.doseAlerts,
            onChanged: (v) {
              Analytics.track('push_toggle', {'kind': 'dose_alerts', 'on': v});
              notifier.save(prefs.copyWith(doseAlerts: v));
            },
          ),
          SwitchListTile(
            key: const Key('push-digest'),
            contentPadding: pad,
            secondary: Icon(Icons.summarize_outlined, color: scheme.primary),
            title: const Text('Tóm tắt cuối ngày', style: titleStyle),
            subtitle: const Text('Khoảng 20:00: huyết áp và số cữ thuốc đã uống'),
            value: prefs.digest,
            onChanged: (v) {
              Analytics.track('push_toggle', {'kind': 'digest', 'on': v});
              notifier.save(prefs.copyWith(digest: v));
            },
          ),
          ListTile(
            key: const Key('push-quiet'),
            contentPadding: pad,
            minTileHeight: 64,
            leading: Icon(Icons.bedtime_outlined, color: scheme.primary),
            title: const Text('Giờ yên tĩnh', style: titleStyle),
            subtitle: Text(
              prefs.hasQuiet
                  ? '${prefs.quietStart} đến ${prefs.quietEnd}. SOS và huyết áp rất cao vẫn báo.'
                  : 'Không dùng. Chạm để chọn giờ không muốn bị báo.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickQuiet(context, prefs, notifier),
          ),
        ],
      ],
    );
  }

  Future<void> _pickQuiet(BuildContext context, PushPrefs prefs, PushPrefsNotifier notifier) async {
    TimeOfDay parse(String? s, TimeOfDay d) {
      if (s == null) return d;
      final p = s.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    Widget h24(BuildContext c, Widget? w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
      child: w!,
    );
    final start = await showTimePicker(
      context: context,
      helpText: 'Bắt đầu yên tĩnh từ',
      initialTime: parse(prefs.quietStart, const TimeOfDay(hour: 22, minute: 0)),
      builder: h24,
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: 'Yên tĩnh đến',
      initialTime: parse(prefs.quietEnd, const TimeOfDay(hour: 6, minute: 0)),
      builder: h24,
    );
    if (end == null) return;
    Analytics.track('push_quiet_set');
    notifier.save(prefs.copyWith(quiet: (start: fmt(start), end: fmt(end))));
  }
}

/// Nhóm "Gia đình": mời người thân theo dõi mình, theo dõi người thân, và công tắc chế độ theo dõi.
class _FamilySettings extends ConsumerWidget {
  const _FamilySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final watchers = ref.watch(watchersProvider);
    final watched = ref.watch(watchedLinksProvider);
    final isFamily = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.family;
    const titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 17);
    return InsetGroup(
      key: const Key('family-settings'),
      dividerIndent: 0,
      children: [
        if (!isFamily)
        ListTile(
          key: const Key('profile-invite'),
          minTileHeight: 64,
          leading: Icon(Icons.family_restroom_outlined, color: scheme.primary),
          title: const Text('Mời người thân theo dõi bác', style: titleStyle),
          subtitle: Text(
            watchers.isEmpty
                ? 'Con xem được sức khoẻ của bác từ xa'
                : '${watchers.length} người đang theo dõi',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.familyInvite),
        ),
        if (isFamily)
          ListTile(
            key: const Key('profile-my-health'),
            minTileHeight: 64,
            leading: Icon(Icons.favorite_border_rounded, color: scheme.primary),
            title: const Text('Sức khoẻ của tôi', style: titleStyle),
            subtitle: const Text('Huyết áp và lịch thuốc của chính bạn'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go(Routes.bp),
          ),
        if (ref.watch(currentUserProvider.select((u) => u?.role)) != AppRole.elder)
        ListTile(
          key: const Key('profile-role'),
          minTileHeight: 64,
          leading: Icon(Icons.swap_horiz_rounded, color: scheme.primary),
          title: const Text('Vai trò', style: titleStyle),
          subtitle: Text(ref.watch(currentUserProvider)?.role?.label ?? 'Chưa chọn'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.chooseRoleChange),
        ),
        if (!isFamily)
        ListTile(
          key: const Key('profile-emergency-card'),
          minTileHeight: 64,
          leading: Icon(Icons.medical_information_outlined, color: scheme.primary),
          title: const Text('Thẻ y tế khẩn cấp', style: titleStyle),
          subtitle: const Text('Nhóm máu, dị ứng, người liên hệ. Hiện khi bấm SOS'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            final me = ref.read(currentUserProvider)?.id;
            if (me != null) context.push(Routes.emergencyCardFor(me));
          },
        ),
        ListTile(
          key: const Key('profile-join'),
          minTileHeight: 64,
          leading: Icon(Icons.person_add_alt_1_outlined, color: scheme.primary),
          title: Text(isFamily ? 'Thêm người thân để theo dõi' : 'Theo dõi người thân', style: titleStyle),
          subtitle: Text(
            watched.isEmpty
                ? 'Nhập mã của cha mẹ'
                : 'Đang theo dõi ${watched.length} người',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.familyJoin),
        ),
        if (watched.isNotEmpty && ref.watch(currentUserProvider)?.role == null)
          SwitchListTile(
            key: const Key('profile-watch-mode'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            secondary: Icon(Icons.visibility_outlined, color: scheme.primary),
            title: const Text('Chế độ theo dõi người thân', style: titleStyle),
            subtitle: const Text('Trang chủ hiện tình hình của cha mẹ'),
            value: ref.watch(watchModeProvider),
            onChanged: (v) {
              Analytics.track('watch_mode', {'on': v});
              ref.read(watchModeProvider.notifier).set(v);
            },
          ),
      ],
    );
  }
}
