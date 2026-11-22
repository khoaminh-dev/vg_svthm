import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../bp/data/bp_reminder_service.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../bp/presentation/providers/bp_reminder_providers.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../push/push_service.dart';
import '../core/control_registry.dart';
import '../core/vy_card.dart';
import '../core/vy_context.dart';
import '../core/vy_core.dart';
import '../core/vy_cursor.dart';
import '../core/vy_reminders.dart';
import '../core/vy_settings.dart';
import '../data/voice_actions.dart';
import '../live/live_state.dart';

/// Nhịp kiểm tra việc cần nhắc.
const _checkEvery = Duration(seconds: 30);

/// Hỏi tin nhắn mới nhiều nhất chừng này một lần (đỡ tốn truy vấn).
const _messagePoll = Duration(minutes: 2);

/// Vy tự nhắc (kế hoạch 9.3): định kỳ xem có việc cần nhắc không, và nếu có thì `VyCore.remind` (Vy thường, miễn phí).
/// Chỉ chạy cho người cao tuổi và chỉ khi app ở nền trước; nền sau/khoá màn hình đã có báo thức và thông báo sẵn.
/// Phần quyết định nằm ở `core/vy_reminders.dart` (thuần, đã kiểm thử); đây chỉ gom dữ liệu và dựng thẻ.
class ProactiveRemindersHost extends ConsumerStatefulWidget {
  const ProactiveRemindersHost({super.key});

  @override
  ConsumerState<ProactiveRemindersHost> createState() => _ProactiveRemindersHostState();
}

class _ProactiveRemindersHostState extends ConsumerState<ProactiveRemindersHost> {
  final _mem = ReminderMemory();
  final DateTime _start = DateTime.now();
  Timer? _timer;
  Timer? _first;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  List<({String roomId, String from, DateTime at})> _incoming = const [];
  bool _checking = false;
  bool _loaded = false;
  static const _kShown = 'vy_remind_shown';

  Dose? _dose; // cữ kế tiếp (do build giữ sống)
  List<DateTime> _measured = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMemory());
    _timer = Timer.periodic(_checkEvery, (_) => unawaited(check()));
    // Nhịp đầu sớm một chút sau khi vào app (dữ liệu thuốc đã tải).
    _first = Timer(const Duration(seconds: 8), () => unawaited(check()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _first?.cancel();
    super.dispose();
  }

  /// Nhớ việc đã nhắc qua các lần mở app: mở lại thì không nhắc lại đúng cữ thuốc/giờ đo vừa nhắc.
  Future<void> _loadMemory() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kShown);
      if (raw != null) {
        final m = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
        _mem.restore(m, DateTime.now());
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _saveMemory(DateTime now) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kShown, jsonEncode(_mem.snapshot(now)));
    } catch (_) {}
  }

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// Một nhịp kiểm tra. Công khai để kiểm thử/gọi tay.
  Future<void> check({DateTime? at}) async {
    if (!mounted || _checking || !_loaded) return;
    _checking = true;
    try {
      final now = at ?? DateTime.now();
      final settings = ref.read(vySettingsProvider).value ?? const VySettings();
      final router = ref.read(routerProvider);
      final path = topRoutePath(router);
      final openRoom = RegExp(r'^/rooms/([^/]+)$').firstMatch(path)?.group(1);
      final core = ref.read(vyCoreProvider);

      // Tin nhắn mới: hỏi theo nhịp riêng; tin ở phòng đang mở coi như đã xem.
      if (settings.remindMessages && now.difference(_lastPoll) >= _messagePoll && _foreground) {
        _lastPoll = now;
        try {
          final list = await ref.refresh(recentIncomingMessagesProvider.future);
          _incoming = [for (final m in list) (roomId: m.roomId, from: m.from, at: m.at)];
        } catch (_) {}
      }
      final groups = groupNewMessages(_incoming, since: _start);
      for (final g in groups) {
        if (g.roomId == openRoom) _mem.done.add('msg:${g.roomId}:${g.latest.millisecondsSinceEpoch}');
      }

      final prefs = ref.read(pushPrefsProvider).value;
      final quiet = inQuietHours(now, prefs?.quietStart, prefs?.quietEnd);

      String? doseKey;
      final d = _dose;
      if (d != null &&
          doseIsDueForReminder(
            now: now,
            dueAt: d.dueAt,
            windowEnd: d.windowEnd,
            pending: d.status == 'pending',
            snoozedUntil: d.snoozedUntil,
          )) {
        doseKey = doseReminderKey(d.id, d.snoozedUntil);
      }

      String? doseCheckKey;
      if (d != null) {
        doseCheckKey = doseFollowUpKey(
          doseId: d.id,
          now: now,
          dueAt: d.dueAt,
          windowEnd: d.windowEnd,
          pending: d.status == 'pending',
          snoozedUntil: d.snoozedUntil,
        );
      }

      final bpSettings = ref.read(bpReminderSettingsProvider).value ?? const BpReminderSettings();
      final bp = bpSettings.effectiveEnabled(elder: true) ? bpReminderDue(now, bpSettings.slots, _measured) : null;

      final busy = core.isOpen ||
          ref.read(liveActiveProvider) ||
          ref.read(vyCursorProvider).active ||
          ref.read(vyCardProvider) != null ||
          ref.read(controlRegistryProvider).hasDialog ||
          path.startsWith('/sos') ||
          path == Routes.measure;

      final pick = decideReminder(
        ReminderInputs(
          now: now,
          foreground: _foreground,
          busy: busy,
          enabledDose: settings.remindDose,
          enabledBp: settings.remindBp,
          enabledMessages: settings.remindMessages,
          quiet: quiet,
          doseKey: doseKey,
          doseCheckKey: doseCheckKey,
          bpDue: bp,
          messages: [for (final g in groups) if (g.roomId != openRoom) g],
        ),
        _mem,
      );
      if (pick == null) return;
      await _show(pick, groups, d);
      _mem.markShown(pick, now);
      unawaited(_saveMemory(now));
    } finally {
      _checking = false;
    }
  }

  Future<void> _show(ReminderPick pick, List<NewMessages> groups, Dose? dose) async {
    final actions = ref.read(voiceActionsProvider);
    final core = ref.read(vyCoreProvider.notifier);
    final hon = await actions.loadHonorific();
    final router = ref.read(routerProvider);
    switch (pick.kind) {
      case ReminderKind.dose:
        final d = dose;
        if (d == null) return;
        final repo = ref.read(medsRepositoryProvider);
        void refresh() => ref
          ..invalidate(myDosesProvider)
          ..invalidate(myPlansProvider);
        await core.remind(
          kind: 'dose',
          speech: reminderSpeech(ReminderKind.dose, hon, doseWhat: d.what),
          card: NoticeCard(
            title: 'Đến giờ uống thuốc',
            body: '${d.hm} · ${d.bag ? 'Túi ' : ''}${d.label}${d.items.isEmpty ? '' : '\n${d.items.map((i) => i.text).join('; ')}'}',
            actions: [
              VyCardAction(
                label: 'Đã uống',
                primary: true,
                run: () async {
                  Analytics.track('vy_remind_reply', {'kind': 'dose', 'reply': 'taken'});
                  try {
                    await repo.setDose(d.id, 'taken');
                  } catch (_) {}
                  refresh();
                },
              ),
              VyCardAction(
                label: 'Lát nữa nhắc',
                run: () async {
                  Analytics.track('vy_remind_reply', {'kind': 'dose', 'reply': 'snooze'});
                  try {
                    await repo.snooze(d.id, 15);
                  } catch (_) {}
                  refresh();
                },
              ),
            ],
          ),
        );
      case ReminderKind.doseCheck:
        final d = dose;
        if (d == null) return;
        final repo = ref.read(medsRepositoryProvider);
        void refresh() => ref
          ..invalidate(myDosesProvider)
          ..invalidate(myPlansProvider);
        await core.remind(
          kind: 'dose_check',
          speech: reminderSpeech(ReminderKind.doseCheck, hon, doseWhat: '${d.bag ? 'túi ' : ''}${d.label.toLowerCase()}'),
          card: NoticeCard(
            title: 'Đã uống thuốc chưa ạ?',
            body: '${d.hm} · ${d.bag ? 'Túi ' : ''}${d.label}${d.items.isEmpty ? '' : '\n${d.items.map((i) => i.text).join('; ')}'}',
            actions: [
              VyCardAction(
                label: 'Đã uống rồi',
                primary: true,
                run: () async {
                  Analytics.track('vy_remind_reply', {'kind': 'dose_check', 'reply': 'taken'});
                  try {
                    await repo.setDose(d.id, 'taken');
                  } catch (_) {}
                  refresh();
                },
              ),
              VyCardAction(
                label: 'Chưa, nhắc lại sau',
                run: () async {
                  Analytics.track('vy_remind_reply', {'kind': 'dose_check', 'reply': 'snooze'});
                  try {
                    await repo.snooze(d.id, 15);
                  } catch (_) {}
                  refresh();
                },
              ),
            ],
          ),
        );
      case ReminderKind.bp:
        await core.remind(
          kind: 'bp',
          speech: reminderSpeech(ReminderKind.bp, hon),
          card: NoticeCard(
            title: 'Đến giờ đo huyết áp',
            body: 'Hôm nay ${hon.isEmpty ? 'bác' : hon} chưa đo.',
            actions: [
              VyCardAction(
                label: 'Đo bây giờ',
                primary: true,
                run: () {
                  Analytics.track('vy_remind_reply', {'kind': 'bp', 'reply': 'measure'});
                  router.push(Routes.measure);
                },
              ),
              VyCardAction(label: 'Để sau', run: () => Analytics.track('vy_remind_reply', {'kind': 'bp', 'reply': 'later'})),
            ],
          ),
        );
      case ReminderKind.messages:
        final g = groups.where((m) => 'msg:${m.roomId}:${m.latest.millisecondsSinceEpoch}' == pick.key).firstOrNull;
        if (g == null) return;
        await core.remind(
          kind: 'messages',
          speech: reminderSpeech(ReminderKind.messages, hon, from: g.from, count: g.count),
          card: NoticeCard(
            title: 'Tin nhắn mới',
            body: g.count > 1 ? '${g.count} tin từ ${g.from}' : 'Tin từ ${g.from}',
            actions: [
              VyCardAction(
                label: 'Nghe',
                primary: true,
                keepOpen: true,
                run: () {
                  Analytics.track('vy_remind_reply', {'kind': 'messages', 'reply': 'listen'});
                  unawaited(core.sendText('đọc tin nhắn'));
                },
              ),
              VyCardAction(
                label: 'Để sau',
                run: () {
                  Analytics.track('vy_remind_reply', {'kind': 'messages', 'reply': 'later'});
                  _mem.later(pick);
                },
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Giữ các nguồn dữ liệu sống (không truy vấn mới mỗi nhịp kiểm tra) và ghi nhận giá trị mới nhất.
    _dose = ref.watch(nextDoseProvider);
    _measured = [for (final r in ref.watch(bpReadingsProvider).value ?? const []) r.measuredAt];
    return const SizedBox.shrink();
  }
}
