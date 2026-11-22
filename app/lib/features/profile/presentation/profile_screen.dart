import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../../voice/core/control_registry.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/domain/plan_models.dart';
import '../data/phone_repository.dart';
import '../../voice/core/vy_settings.dart';
import '../../../shared/honorific.dart';

/// Dòng phụ của mục "Gói Vy Live" ở Hồ sơ.
String _planSubtitle(AsyncValue<PlanOverview> a) {
  final o = a.value;
  if (o == null) return 'Xem và đăng ký gói';
  final mine = o.mine;
  if (o.live) {
    final until = mine != null && mine.isLiveAt(DateTime.now()) ? mine.expiresAt : null;
    return until != null ? 'Đang bật đến ${formatDay(until)}' : 'Đang bật (do ${o.coveredBy ?? 'người thân'} đăng ký)';
  }
  if (mine != null && mine.isPending) return 'Yêu cầu đang chờ duyệt';
  return 'Chưa đăng ký';
}

/// Tab Hồ sơ: thông tin tài khoản, phiên bản app và đăng xuất.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => VyControlScope(
        dialogId: 'dlg.logout',
        dialogTitle: 'Đăng xuất khỏi Viegrand?',
        controls: [
          VyControl(
            id: 'dlg.logout.ok',
            label: 'Đăng xuất',
            aliases: const ['đồng ý', 'có', 'chắc chắn'],
            level: VyLevel.selfOnly, // Vy không bao giờ đăng xuất thay người dùng
          ),
          VyControl(
            id: 'dlg.logout.stay',
            label: 'Ở lại',
            aliases: const ['không', 'thôi', 'huỷ', 'hủy', 'không đăng xuất'],
            onInvoke: () => Navigator.pop(ctx, false),
          ),
        ],
        child: AlertDialog(
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
    final isElder = user?.role == AppRole.elder;
    final vySet = ref.watch(vySettingsProvider).value ?? const VySettings();
    final speakOn = ref.watch(speakAdviceProvider).value ?? true;
    final bpRemind = (ref.watch(bpReminderSettingsProvider).value ?? const BpReminderSettings())
        .effectiveEnabled(elder: isElder);
    final pushPrefs = ref.watch(pushPrefsProvider).value ?? const PushPrefs();
    final controls = <VyControl>[
      VyControl(
        id: 'prof.captions',
        label: 'Hiện chữ khi Vy nói',
        aliases: const ['chữ phụ đề', 'phụ đề', 'chữ khi vy nói'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.captions,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setCaptions(v),
      ),
      VyControl(
        id: 'prof.textinput',
        label: 'Ô gõ chữ cho Vy',
        aliases: const ['gõ chữ cho vy', 'bàn phím cho vy', 'ô gõ chữ'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.textInput,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setTextInput(v),
      ),
      VyControl(
        id: 'prof.sounds',
        label: 'Tiếng khi bật và tắt Vy',
        aliases: const ['tiếng ting', 'âm thanh vy'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.sounds,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setSounds(v),
      ),
      VyControl(
        id: 'prof.remind.dose',
        label: 'Vy tự nhắc uống thuốc',
        aliases: const ['nhắc uống thuốc', 'tự nhắc uống thuốc'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.remindDose,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setRemind(dose: v),
      ),
      VyControl(
        id: 'prof.remind.bp',
        label: 'Vy tự nhắc đo huyết áp',
        aliases: const ['tự nhắc đo huyết áp'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.remindBp,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setRemind(bp: v),
      ),
      VyControl(
        id: 'prof.remind.msg',
        label: 'Vy tự nhắc tin nhắn mới',
        aliases: const ['nhắc tin nhắn', 'tự nhắc tin nhắn'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: vySet.remindMessages,
        onSet: (v) => ref.read(vySettingsProvider.notifier).setRemind(messages: v),
      ),
      VyControl(
        id: 'prof.speak',
        label: 'Đọc lời khuyên sau khi đo',
        aliases: const ['đọc lời khuyên', 'lời khuyên'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: speakOn,
        onSet: (v) => ref.read(speakAdviceProvider.notifier).set(v),
      ),
      VyControl(
        id: 'prof.bpremind',
        label: 'Nhắc đo huyết áp',
        aliases: const ['nhắc nhở đo huyết áp'],
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: bpRemind,
        onSet: (v) => ref.read(bpReminderSettingsProvider.notifier).setEnabled(v),
      ),
      VyControl(
        id: 'prof.push',
        label: 'Thông báo tin nhắn',
        kind: VyKind.toggle,
        level: VyLevel.readBack,
        value: pushPrefs.messages,
        onSet: (v) => ref.read(pushPrefsProvider.notifier).save(pushPrefs.copyWith(messages: v)),
      ),
      if (user != null) ...[
        VyControl(
          id: 'prof.invite',
          label: 'Mời người thân',
          aliases: const ['mã mời'],
          onInvoke: () => context.push(Routes.familyInvite),
        ),
        VyControl(
          id: 'prof.emergency',
          label: 'Thẻ y tế khẩn cấp',
          aliases: const ['thẻ y tế'],
          onInvoke: () => context.push(Routes.emergencyCardFor(user.id)),
        ),
        VyControl(
          id: 'prof.health',
          label: 'Hồ sơ sức khoẻ',
          onInvoke: () => context.push(Routes.healthProfile),
        ),
      ],
      // Việc không hoàn tác được hoặc đổi quyền: mức 3, Vy chỉ nhắc, người dùng tự bấm.
      const VyControl(
        id: 'prof.role',
        label: 'Đổi vai trò',
        level: VyLevel.selfOnly,
      ),
      VyControl(
        id: 'prof.logout',
        label: 'Đăng xuất',
        aliases: const ['thoát tài khoản'],
        level: VyLevel.selfOnly,
        onInvoke: () => _confirmSignOut(context, ref),
      ),
    ];

    Widget row(IconData icon, String label, String value) => ListTile(
      minTileHeight: 64,
      leading: _LeadIcon(icon),
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
      secondary: const _LeadIcon(Icons.volume_up_outlined),
      title: const Text(
        'Đọc lời khuyên sau khi đo',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      subtitle: Text(user?.role == AppRole.family ? 'Máy tự đọc to cho bạn nghe' : hon('Máy tự đọc to cho bác nghe')),
      value: ref.watch(speakAdviceProvider).value ?? true,
      onChanged: (v) {
        Analytics.track('speak_advice_toggle', {'on': v});
        ref.read(speakAdviceProvider.notifier).set(v);
      },
    );

    return VyControlScope(
      controls: controls,
      child: Scaffold(
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
                        leading: _LeadIcon(Icons.assignment_ind_outlined),
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
                  const _PhoneSettings(elder: true),
                  const SizedBox(height: AppSpacing.md),
                  const _BpReminderSettings(elder: true),
                  const SizedBox(height: AppSpacing.md),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const Key('profile-more'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                      collapsedBackgroundColor: Colors.white,
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      title: const Text(
                        'Cài đặt khác',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.navyDeep),
                      ),
                      children: [
                        InsetGroup(dividerIndent: 0, children: [speakTile]),
                        const SizedBox(height: AppSpacing.md),
                        const _VySettingsGroup(),
                        const SizedBox(height: AppSpacing.md),
                        const _FamilySettings(hideShortcuts: true),
                        const SizedBox(height: AppSpacing.md),
                        const _NotificationSettings(),
                      ],
                    ),
                  ),
                ] else ...[
                  const _BpReminderSettings(elder: false),
                  const SizedBox(height: AppSpacing.lg),
                  const _PhoneSettings(),
                  const SizedBox(height: AppSpacing.lg),
                  const _VySettingsGroup(),
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
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _VersionLabel(
                  style: text.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Dòng phiên bản. Chạm 7 lần liên tiếp mở màn thử nghiệm nội bộ Vy Live (chỉ tài khoản được bật ở máy chủ dùng được).
class _VersionLabel extends StatefulWidget {
  const _VersionLabel({this.style});

  final TextStyle? style;

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Màn thử Vy Live chỉ mở được ở bản gỡ lỗi hoặc build nội bộ (`--dart-define=VG_LAB=true`).
  static const _labEnabled = bool.fromEnvironment('VG_LAB');

  void _tap() {
    if (!(kDebugMode || _labEnabled)) return;
    final now = DateTime.now();
    _taps = now.difference(_last) > const Duration(seconds: 2) ? 1 : _taps + 1;
    _last = now;
    if (_taps >= 7) {
      _taps = 0;
      context.push(Routes.liveLab);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final i = snap.data;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Text(
            i == null ? '' : 'Viegrand ${i.version} (${i.buildNumber})',
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        );
      },
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
        elevation: 1.5,
        shadowColor: AppColors.cardShadow,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF0FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: AppColors.navyDeep),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.navyDeep)),
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 28, color: Color(0xFFB8BEC9)),
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
          watchers.isEmpty ? hon('Để con xem được sức khoẻ của bác') : '${watchers.length} người đang theo dõi',
          () => context.push(Routes.familyInvite),
        ),
        big(
          'profile-plan',
          Icons.workspace_premium_outlined,
          'Gói Vy Live',
          _planSubtitle(ref.watch(planOverviewProvider)),
          () => context.push(Routes.plan),
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
    final s = ref.watch(bpReminderSettingsProvider).value ?? const BpReminderSettings();
    final n = ref.read(bpReminderSettingsProvider.notifier);
    final on = s.effectiveEnabled(elder: elder);
    final titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: elder ? 20 : 17);
    final subStyle = TextStyle(fontSize: elder ? 17 : 14);
    const pad = EdgeInsets.symmetric(horizontal: 16);
    return InsetGroup(
      key: const Key('bp-reminder-settings'),
      dividerIndent: 0,
      children: [
        SwitchListTile(
          key: const Key('bp-reminder-toggle'),
          contentPadding: pad,
          secondary: _LeadIcon(Icons.alarm_on_rounded, size: elder ? 48 : 38),
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
            leading: _LeadIcon(Icons.wb_sunny_outlined, size: elder ? 48 : 38),
            title: Text('Buổi sáng', style: titleStyle),
            subtitle: Text('Chạm để đổi giờ', style: subStyle),
            trailing: Text(
              s.morning,
              style: TextStyle(fontSize: elder ? 28 : 20, fontWeight: FontWeight.w700),
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
            leading: _LeadIcon(Icons.nights_stay_outlined, size: elder ? 48 : 38),
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
                        style: TextStyle(fontSize: elder ? 28 : 20, fontWeight: FontWeight.w700),
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
          secondary: _LeadIcon(Icons.notifications_outlined),
          title: const Text('Thông báo tin nhắn', style: titleStyle),
          subtitle: Text(ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.family ? 'Báo khi có người nhắn cho bạn' : hon('Báo khi có người nhắn cho bác')),
          value: prefs.messages,
          onChanged: (v) {
            Analytics.track('push_toggle', {'kind': 'messages', 'on': v});
            notifier.save(prefs.copyWith(messages: v));
          },
        ),
        SwitchListTile(
          key: const Key('push-show-text'),
          contentPadding: pad,
          secondary: _LeadIcon(Icons.visibility_outlined),
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
          secondary: _LeadIcon(Icons.system_update_outlined),
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
            secondary: _LeadIcon(Icons.medication_outlined),
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
            secondary: _LeadIcon(Icons.summarize_outlined),
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
            leading: _LeadIcon(Icons.bedtime_outlined),
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
  const _FamilySettings({this.hideShortcuts = false});

  /// Người cao tuổi đã có ô lớn "Mời người thân" và "Thẻ y tế khẩn cấp" ở đầu trang: không lặp lại.
  final bool hideShortcuts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchers = ref.watch(watchersProvider);
    final watched = ref.watch(watchedLinksProvider);
    final isFamily = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.family;
    const titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 17);
    return InsetGroup(
      key: const Key('family-settings'),
      dividerIndent: 0,
      children: [
        if (!isFamily && !hideShortcuts)
        ListTile(
          key: const Key('profile-invite'),
          minTileHeight: 64,
          leading: _LeadIcon(Icons.family_restroom_outlined),
          title: Text(hon('Mời người thân theo dõi bác'), style: titleStyle),
          subtitle: Text(
            watchers.isEmpty
                ? hon('Con xem được sức khoẻ của bác từ xa')
                : '${watchers.length} người đang theo dõi',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.familyInvite),
        ),
        if (isFamily)
          ListTile(
            key: const Key('profile-my-health'),
            minTileHeight: 64,
            leading: _LeadIcon(Icons.favorite_border_rounded),
            title: const Text('Sức khoẻ của tôi', style: titleStyle),
            subtitle: const Text('Huyết áp và lịch thuốc của chính bạn'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go(Routes.bp),
          ),
        if (!hideShortcuts)
        ListTile(
          key: const Key('profile-plan'),
          minTileHeight: 64,
          leading: _LeadIcon(Icons.workspace_premium_outlined),
          title: const Text('Gói Vy Live', style: titleStyle),
          subtitle: Text(_planSubtitle(ref.watch(planOverviewProvider))),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.plan),
        ),
        ListTile(
          key: const Key('profile-role'),
          minTileHeight: 64,
          leading: _LeadIcon(Icons.swap_horiz_rounded),
          title: const Text('Đổi vai trò', style: titleStyle),
          subtitle: Text('Đang là: ${ref.watch(currentUserProvider)?.role?.label ?? 'chưa chọn'}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.chooseRoleChange),
        ),
        if (!isFamily && !hideShortcuts)
        ListTile(
          key: const Key('profile-emergency-card'),
          minTileHeight: 64,
          leading: _LeadIcon(Icons.medical_information_outlined),
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
          leading: _LeadIcon(Icons.person_add_alt_1_outlined),
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
            secondary: _LeadIcon(Icons.visibility_outlined),
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


/// Biểu tượng ở đầu dòng cài đặt: ô bo góc tô nhạt (như màn Cài đặt của iOS).
class _LeadIcon extends StatelessWidget {
  const _LeadIcon(this.icon, {this.size = 38});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF0FF),
      borderRadius: BorderRadius.circular(size * 0.29),
    ),
    child: Icon(icon, size: size * 0.58, color: AppColors.navyDeep),
  );
}


/// Cài đặt Vy: hiện chữ khi Vy nói (cho người nghe kém hoặc nơi ồn) và tiếng bật/tắt Vy.
class _VySettingsGroup extends ConsumerWidget {
  const _VySettingsGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(vySettingsProvider).value ?? const VySettings();
    final n = ref.read(vySettingsProvider.notifier);
    const pad = EdgeInsets.symmetric(horizontal: 16);
    const titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 17);
    return InsetGroup(
      key: const Key('vy-settings'),
      dividerIndent: 0,
      children: [
        SwitchListTile(
          key: const Key('vy-captions'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.subtitles_outlined),
          title: const Text('Hiện chữ khi Vy nói', style: titleStyle),
          subtitle: const Text('Vy nói gì thì hiện chữ trên màn hình'),
          value: s.captions,
          onChanged: (v) {
            Analytics.track('vy_setting', {'captions': v});
            n.setCaptions(v);
          },
        ),
        SwitchListTile(
          key: const Key('vy-textinput'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.keyboard_alt_outlined),
          title: const Text('Ô gõ chữ cho Vy', style: titleStyle),
          subtitle: const Text('Hiện ô để gõ chữ thay vì nói'),
          value: s.textInput,
          onChanged: (v) {
            Analytics.track('vy_setting', {'text_input': v});
            n.setTextInput(v);
          },
        ),
        SwitchListTile(
          key: const Key('vy-remind-dose'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.medication_outlined),
          title: const Text('Vy tự nhắc uống thuốc', style: titleStyle),
          subtitle: const Text('Đến giờ thì Vy hiện lên và nhắc'),
          value: s.remindDose,
          onChanged: (v) {
            Analytics.track('vy_setting', {'remind_dose': v});
            n.setRemind(dose: v);
          },
        ),
        SwitchListTile(
          key: const Key('vy-remind-bp'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.monitor_heart_outlined),
          title: const Text('Vy tự nhắc đo huyết áp', style: titleStyle),
          subtitle: const Text('Theo giờ nhắc đo, nếu hôm nay chưa đo'),
          value: s.remindBp,
          onChanged: (v) {
            Analytics.track('vy_setting', {'remind_bp': v});
            n.setRemind(bp: v);
          },
        ),
        SwitchListTile(
          key: const Key('vy-remind-msg'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.chat_bubble_outline_rounded),
          title: const Text('Vy tự nhắc tin nhắn mới', style: titleStyle),
          subtitle: Text(hon('Hỏi bác có muốn nghe không')),
          value: s.remindMessages,
          onChanged: (v) {
            Analytics.track('vy_setting', {'remind_msg': v});
            n.setRemind(messages: v);
          },
        ),
        SwitchListTile(
          key: const Key('vy-sounds'),
          contentPadding: pad,
          secondary: const _LeadIcon(Icons.music_note_outlined),
          title: const Text('Tiếng khi bật và tắt Vy', style: titleStyle),
          subtitle: const Text('Một tiếng ting ngắn'),
          value: s.sounds,
          onChanged: (v) {
            Analytics.track('vy_setting', {'sounds': v});
            n.setSounds(v);
          },
        ),
      ],
    );
  }
}


/// Số điện thoại của tôi: để người thân đã liên kết nhờ Vy gọi cho mình, và Vy gọi được người thân cho mình ("gọi con trai").
/// Lưu ở bảng riêng `profile_phones`: chỉ mình và người thân ĐANG liên kết thấy, người lạ không thấy.
class _PhoneSettings extends ConsumerWidget {
  const _PhoneSettings({this.elder = false});

  final bool elder;

  Future<void> _edit(BuildContext context, WidgetRef ref, String? current) async {
    final c = TextEditingController(text: current ?? '');
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => VyControlScope(
        dialogId: 'dlg.phone',
        dialogTitle: 'Số điện thoại của tôi',
        controls: [
          VyControl(id: 'dlg.phone.cancel', label: 'Huỷ', aliases: const ['hủy', 'không', 'thôi'], onInvoke: () => Navigator.pop(ctx, false)),
        ],
        child: StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Số điện thoại của tôi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('phone-field'),
                  controller: c,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(hintText: '0901 234 567', errorText: error),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Chỉ người thân đã liên kết với bạn mới thấy số này. Người lạ không thấy.',
                  style: TextStyle(fontSize: 15, color: AppColors.textMuted),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              if ((current ?? '').isNotEmpty)
                TextButton(
                  key: const Key('phone-clear'),
                  onPressed: () async {
                    try {
                      await ref.read(phoneRepositoryProvider).saveMine(null);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setS(() => error = 'Chưa xoá được, thử lại nhé');
                    }
                  },
                  child: const Text('Xoá số'),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
              FilledButton(
                key: const Key('phone-save'),
                style: FilledButton.styleFrom(minimumSize: const Size(110, AppSpacing.tapTarget)),
                onPressed: () async {
                  if (normalizePhone(c.text) == null) {
                    setS(() => error = 'Nhập 8 đến 15 chữ số');
                    return;
                  }
                  try {
                    await ref.read(phoneRepositoryProvider).saveMine(c.text);
                    Analytics.track('phone_saved');
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    setS(() => error = 'Chưa lưu được, thử lại nhé');
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      ),
    );
    c.dispose();
    if (saved == true) ref.invalidate(myPhoneProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(myPhoneProvider).value;
    return InsetGroup(
      key: const Key('phone-settings'),
      dividerIndent: 0,
      children: [
        ListTile(
          key: const Key('phone-row'),
          minTileHeight: elder ? 84 : 64,
          leading: _LeadIcon(Icons.phone_outlined, size: elder ? 52 : 44),
          title: Text('Số điện thoại của tôi', style: TextStyle(fontSize: elder ? 22 : 20, fontWeight: FontWeight.w700)),
          subtitle: Text(
            (phone ?? '').isEmpty ? 'Chưa có. Chạm để thêm số' : phone!,
            style: TextStyle(fontSize: elder ? 20 : 17),
          ),
          trailing: const Icon(Icons.edit_outlined, size: 22),
          onTap: () => _edit(context, ref, phone),
        ),
      ],
    );
  }
}
