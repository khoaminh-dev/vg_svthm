import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../chat/domain/room.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../data/speech_player.dart';
import '../data/thinking_sound.dart';
import '../data/voice_api.dart';
import '../data/voice_recorder.dart';
import '../domain/voice_models.dart';

class VoiceState {
  const VoiceState({
    this.status = VoiceStatus.idle,
    this.panelOpen = false,
    this.transcript = '',
    this.say = '',
    this.chips = const [],
    this.level = 0,
    this.error,
    this.dialog = const VoiceDialog(),
  });

  final VoiceStatus status;
  final bool panelOpen;
  final String transcript;
  final String say;
  final List<String> chips;
  final double level;
  final String? error;
  final VoiceDialog dialog;

  VoiceState copyWith({
    VoiceStatus? status,
    bool? panelOpen,
    String? transcript,
    String? say,
    List<String>? chips,
    double? level,
    Object? error = _keep,
    VoiceDialog? dialog,
  }) => VoiceState(
    status: status ?? this.status,
    panelOpen: panelOpen ?? this.panelOpen,
    transcript: transcript ?? this.transcript,
    say: say ?? this.say,
    chips: chips ?? this.chips,
    level: level ?? this.level,
    error: identical(error, _keep) ? this.error : error as String?,
    dialog: dialog ?? this.dialog,
  );
}

const _keep = Object();

final voiceApiProvider = Provider<VoiceApi>(
  (ref) => VoiceApi(accessToken: () => ref.read(supabaseClientProvider).auth.currentSession?.accessToken),
);

/// Bộ điều khiển hội thoại giọng nói: bấm mic để nói, bấm lại để dừng; trợ lý hỏi xong tự mở mic.
class VoiceController extends Notifier<VoiceState> {
  // Tạo khi dùng lần đầu (không đụng plugin âm thanh khi chưa cần) và huỷ nếu đã tạo.
  VoiceApi? _apiInst;
  VoiceRecorder? _recorderInst;
  SpeechPlayer? _playerInst;
  VoiceApi get _api {
    final VoiceApi v = _apiInst ?? ref.read<VoiceApi>(voiceApiProvider);
    _apiInst = v;
    return v;
  }

  VoiceRecorder get _recorder {
    final v = _recorderInst ?? VoiceRecorder();
    _recorderInst = v;
    return v;
  }

  SpeechPlayer get _player {
    final v = _playerInst ?? SpeechPlayer(_api);
    _playerInst = v;
    return v;
  }

  ThinkingSound? _soundInst;
  ThinkingSound get _sound => _soundInst ??= ThinkingSound();

  /// Lệnh đổi màn hình: chạy xong thì thu gọn màn Vy để người dùng thấy kết quả (Vy vẫn đọc nốt câu trả lời).
  static const _navIntents = {
    'send_message',
    'open_chat',
    'open_feature',
    'measure_bp',
    'show_bp',
    'go_home',
    'go_back',
  };

  String _session = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  int _turnNo = 0;
  int _run = 0; // tăng mỗi lần huỷ/bắt đầu để bỏ kết quả cũ
  int _silentRounds = 0;
  String _honorific = 'bác';
  Map<String, List<String>> _aliases = {};
  bool _prefsLoaded = false;
  String? _lastSay;
  String _lastSayClass = 'static';

  @override
  VoiceState build() {
    ref.onDispose(() {
      final r = _recorderInst, p = _playerInst, s = _soundInst;
      if (r != null) unawaited(r.dispose());
      if (p != null) unawaited(p.dispose());
      if (s != null) unawaited(s.dispose());
    });
    // Âm thanh "đang nghĩ" chỉ chạy khi trạng thái là thinking.
    listenSelf((prev, next) {
      final was = prev?.status == VoiceStatus.thinking;
      final now = next.status == VoiceStatus.thinking;
      if (now && !was) unawaited(_sound.start());
      if (!now && was) unawaited(_sound.stop());
    });
    return const VoiceState();
  }

  // ---------- Điều khiển từ giao diện ----------

  /// Nút mic: nghe → dừng và gửi; đang đọc/xử lý → ngắt và nghe ngay.
  Future<void> toggle() async {
    switch (state.status) {
      case VoiceStatus.listening:
        Analytics.track('voice_mic_stop');
        await _recorder.stop();
      case VoiceStatus.speaking:
        Analytics.track('voice_barge_in');
        await _player.stop();
        state = state.copyWith(panelOpen: true);
        await _listen();
      case VoiceStatus.thinking:
        _cancelRun();
        state = state.copyWith(status: VoiceStatus.idle);
      case VoiceStatus.idle:
        Analytics.track('voice_mic_start');
        unawaited(_sound.warmUp());
        _newSession();
        state = state.copyWith(panelOpen: true, transcript: '', say: '', chips: const [], error: null);
        await _listen();
    }
  }

  /// Đóng bảng trợ lý và dừng mọi thứ.
  Future<void> close() async {
    _cancelRun();
    Analytics.track('voice_close');
    state = const VoiceState();
  }

  /// Bấm một gợi ý (chip): coi như người dùng vừa nói câu đó.
  Future<void> tapChip(String text) async {
    if (state.status == VoiceStatus.thinking) return;
    await _player.stop();
    await _recorder.cancel();
    Analytics.track('voice_chip');
    await _send(text: text);
  }

  void _cancelRun() {
    _run++;
    unawaited(_recorder.cancel());
    unawaited(_player.stop());
  }

  void _newSession() {
    _session = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _turnNo = 0;
    _silentRounds = 0;
    state = state.copyWith(dialog: const VoiceDialog());
  }

  // ---------- Vòng hội thoại ----------

  Future<void> _listen() async {
    final run = ++_run;
    if (!await _recorder.ensurePermission()) {
      state = state.copyWith(
        status: VoiceStatus.idle,
        error: 'Cần cho phép dùng micro để nói chuyện với trợ lý.',
      );
      return;
    }
    await _player.stop();
    state = state.copyWith(status: VoiceStatus.listening, error: null, level: 0);
    final clip = await _recorder.record(onLevel: (l) {
      if (run == _run && state.status == VoiceStatus.listening) state = state.copyWith(level: l);
    });
    if (run != _run) return;
    if (clip == null) {
      state = state.copyWith(status: VoiceStatus.idle);
      return;
    }
    if (!clip.heardSpeech || clip.durationMs < 400) {
      // Không nghe thấy gì: hỏi lại tối đa 2 lần rồi nghỉ, tránh vòng lặp vô tận.
      _silentRounds++;
      Analytics.track('voice_no_speech');
      if (_silentRounds >= 2) {
        _silentRounds = 0;
        state = state.copyWith(status: VoiceStatus.idle, say: 'Con chưa nghe thấy gì. Bấm micro để nói lại nhé.');
        return;
      }
      await _speakAndMaybeListen(
        '${_honorific[0].toUpperCase()}${_honorific.substring(1)} nói to hơn một chút giúp con nhé.',
        'other',
        listenAfter: true,
        run: run,
      );
      return;
    }
    _silentRounds = 0;
    await _send(audio: clip, run: run);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final c = ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      if (uid == null) return;
      final p = await c.from('voice_prefs').select('honorific').eq('user_id', uid).maybeSingle();
      if (p != null) _honorific = p['honorific'] as String? ?? 'bác';
    } catch (_) {}
  }

  Future<List<VoiceContact>> _contacts() async {
    try {
      final c = ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      final rooms = await ref.read(roomsProvider.future);
      try {
        final rows = await c.from('voice_aliases').select('alias_norm, contact_id').eq('user_id', uid ?? '');
        final m = <String, List<String>>{};
        for (final r in rows) {
          (m[r['contact_id'] as String] ??= []).add(r['alias_norm'] as String);
        }
        _aliases = m;
      } catch (_) {}
      return [
        for (final r in rooms)
          VoiceContact(
            id: r.id,
            kind: r.isDirect ? 'direct' : 'group',
            name: r.displayName,
            username: r.peer?.username,
            aliases: _aliases[r.id] ?? const [],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  String? _currentRoomId() {
    final path = currentPath(ref.read(routerProvider));
    final m = RegExp(r'^/rooms/([^/]+)$').firstMatch(path);
    return m?.group(1);
  }

  String _screenName() => currentPath(ref.read(routerProvider));

  Future<void> _send({VoiceClipArg? audio, String? text, int? run}) async {
    final myRun = run ?? ++_run;
    state = state.copyWith(status: VoiceStatus.thinking, level: 0, error: null);
    await _loadPrefs();
    final contacts = await _contacts();
    if (myRun != _run) return;
    _turnNo++;
    try {
      final res = await _api.turn(
        sessionId: _session,
        turnNo: _turnNo,
        audio: audio?.bytes,
        durationMs: audio?.durationMs ?? 0,
        text: text,
        dialog: state.dialog,
        screen: _screenName(),
        roomId: _currentRoomId(),
        contacts: contacts,
        honorific: _honorific,
      );
      if (myRun != _run) return;
      await _apply(res, contacts, myRun);
    } on VoiceApiException catch (e) {
      if (myRun != _run) return;
      Analytics.track('voice_error', {'code': e.code});
      state = state.copyWith(status: VoiceStatus.idle, error: e.message);
      unawaited(_player.speak(e.message, sayClass: 'other'));
    }
  }

  Future<void> _apply(VoiceTurnResult res, List<VoiceContact> contacts, int run) async {
    final d = res.decision;
    Analytics.track('voice_turn', {'intent': d.intent ?? '', 'action': d.action});
    var say = d.say;
    var sayClass = d.sayClass;
    var dialog = const VoiceDialog();
    var listenAfter = d.expectsReply;

    switch (d.action) {
      case 'ask' || 'confirm':
        dialog = VoiceDialog(
          task: d.task,
          pending: d.pending,
          expects: d.expects,
          choices: d.choices,
          aliasPhrase: d.aliasPhrase,
        );
      case 'repeat':
        say = _lastSay ?? 'Con chưa nói gì để nhắc lại ạ.';
        sayClass = _lastSayClass;
        dialog = state.dialog;
        listenAfter = state.dialog.expects != VoiceExpect.command;
      case 'execute':
        final out = await _execute(d.task!, contacts);
        if (run != _run) return;
        if (out != null) say = out;
        if (out != null) sayClass = 'other';
      default:
        break;
    }

    _lastSay = say;
    _lastSayClass = sayClass;
    final navigated = d.action == 'execute' && _navIntents.contains(d.task?.intent);
    state = state.copyWith(
      transcript: res.transcript,
      say: say,
      chips: d.chips,
      dialog: dialog,
      status: VoiceStatus.speaking,
      panelOpen: navigated ? false : state.panelOpen,
    );
    await _speakAndMaybeListen(say, sayClass, listenAfter: listenAfter, run: run, alreadySpeaking: true);
  }

  Future<void> _speakAndMaybeListen(
    String say,
    String sayClass, {
    required bool listenAfter,
    required int run,
    bool alreadySpeaking = false,
  }) async {
    if (!alreadySpeaking) state = state.copyWith(status: VoiceStatus.speaking, say: say);
    await _player.speak(say, sayClass: sayClass);
    if (run != _run) return;
    if (listenAfter) {
      await _listen(); // mở mic ngay khi trợ lý nói xong
    } else {
      state = state.copyWith(status: VoiceStatus.idle);
    }
  }

  // ---------- Thực hiện lệnh ----------

  /// Chạy lệnh trên app. Trả về câu nói thay thế (khi cần báo kết quả/lỗi), hoặc null để dùng câu của server.
  Future<String?> _execute(VoiceTask t, List<VoiceContact> contacts) async {
    final router = ref.read(routerProvider);
    final s = t.slots;
    switch (t.intent) {
      case 'send_message':
        final roomId = s['room_id'];
        final content = s['content'];
        if (roomId == null || content == null) return 'Con chưa gửi được, $_honorific thử lại nhé.';
        final ok = await ref.read(chatRepositoryProvider).sendMessage(roomId, content).then((_) => true).catchError((_) => false);
        Analytics.track('voice_send_message', {'ok': ok});
        if (!ok) return 'Con gửi chưa được, $_honorific kiểm tra mạng rồi thử lại nhé.';
        _openRoom(roomId, contacts);
        return null;
      case 'open_chat':
        final id = s['room_id'];
        if (id == null) return null;
        _openRoom(id, contacts);
        return null;
      case 'open_feature':
        switch (s['feature']) {
          case 'chat':
            router.go(Routes.rooms);
          case 'ocr':
            router.go(Routes.measure);
          case 'bp':
            router.go(Routes.bp);
          default:
            router.go(Routes.home);
        }
        return null;
      case 'measure_bp':
        router.go(Routes.measure);
        return 'Dạ, $_honorific chụp màn hình máy đo huyết áp giúp con nhé.';
      case 'show_bp':
        router.go(Routes.bp);
        return null;
      case 'read_bp':
        return await _readBp();
      case 'go_home':
        router.go(Routes.home);
        return null;
      case 'go_back':
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(Routes.home);
        }
        return null;
    }
    return null;
  }

  void _openRoom(String id, List<VoiceContact> contacts) {
    final router = ref.read(routerProvider);
    final rooms = ref.read(roomsProvider).value;
    Room? room;
    if (rooms != null) {
      for (final r in rooms) {
        if (r.id == id) room = r;
      }
    }
    // Đã ở đúng phòng thì không mở chồng lên.
    if (_currentRoomId() == id) return;
    router.go(Routes.rooms);
    router.push(Routes.roomPath(id), extra: room);
  }

  Future<String> _readBp() async {
    try {
      final list = await ref.read(bpReadingsProvider.future);
      if (list.isEmpty) return 'Chưa có kết quả đo nào. ${_honorific[0].toUpperCase()}${_honorific.substring(1)} đo huyết áp rồi chụp lại giúp con nhé.';
      final r = list.reduce((a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b);
      final cat = BpCategory.of(r.systolic, r.diastolic).label;
      final pulse = r.pulse == null ? '' : ', mạch ${r.pulse}';
      return 'Lần đo gần nhất: huyết áp ${r.systolic} trên ${r.diastolic}$pulse. Mức: $cat.';
    } catch (_) {
      return 'Con chưa đọc được kết quả, $_honorific thử lại sau nhé.';
    }
  }
}

/// Âm thanh đã ghi (gọn để truyền vào [VoiceController._send]).
typedef VoiceClipArg = RecordedClip;

final voiceControllerProvider = NotifierProvider<VoiceController, VoiceState>(VoiceController.new);
