import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../presentation/voice_controller.dart';

/// Đợt A (thử nghiệm nội bộ) của Vy Live. Xem docs/PREMIUM_LIVE_DESIGN.md.
/// Chỉ để đo: tiếng Việt, độ trễ, chế độ R (Responses delegation) so với C (client delegation).
/// Các hàm điều hướng/video/nhắn tin chỉ GIẢ LẬP (không đổi màn hình, không gửi tin); `read_bp` đọc thật.

enum LivePhase { idle, connecting, live, closing }

class LiveLabState {
  const LiveLabState({
    this.phase = LivePhase.idle,
    this.mode = 'R',
    this.userText = '',
    this.assistantText = '',
    this.metrics = const {},
    this.log = const [],
    this.error,
  });

  final LivePhase phase;
  final String mode;
  final String userText;
  final String assistantText;
  final Map<String, String> metrics;
  final List<String> log;
  final String? error;

  LiveLabState copyWith({
    LivePhase? phase,
    String? mode,
    String? userText,
    String? assistantText,
    Map<String, String>? metrics,
    List<String>? log,
    Object? error = _keep,
  }) => LiveLabState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    userText: userText ?? this.userText,
    assistantText: assistantText ?? this.assistantText,
    metrics: metrics ?? this.metrics,
    log: log ?? this.log,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

const _keep = Object();

class LiveLabController extends Notifier<LiveLabState> {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;
  Timer? _flushTimer;
  Timer? _closeTimeout;
  final _sw = Stopwatch();
  int _evt = 0;
  final String _honorific = 'bác';

  // Số đo độ trễ (ms trên đồng hồ _sw).
  int _lastUserAt = -1;
  int _delegationAt = -1;
  int _lastResultAt = -1;
  bool _awaitingFirstSpeech = false;
  String _userBuf = '';
  final _pending = <Map<String, Object?>>[];
  final _seenTypes = <String>{};

  @override
  LiveLabState build() {
    ref.onDispose(() => unawaited(_teardown()));
    return const LiveLabState();
  }

  void setMode(String m) {
    if (state.phase == LivePhase.idle) state = state.copyWith(mode: m);
  }

  void _log(String s) {
    final line = '${_sw.isRunning ? _sw.elapsedMilliseconds : 0}ms  $s';
    final next = [...state.log, line];
    state = state.copyWith(log: next.length > 400 ? next.sublist(next.length - 400) : next);
  }

  void _metric(String k, String v) {
    state = state.copyWith(metrics: {...state.metrics, k: v});
    _log('# $k = $v');
  }

  String logText() => state.log.join('\n');

  Future<void> start() async {
    if (state.phase != LivePhase.idle) return;
    _sw
      ..reset()
      ..start();
    _evt = 0;
    _lastUserAt = _delegationAt = _lastResultAt = -1;
    _awaitingFirstSpeech = false;
    _userBuf = '';
    _pending.clear();
    _seenTypes.clear();
    state = LiveLabState(phase: LivePhase.connecting, mode: state.mode, log: const []);
    _log('bắt đầu, chế độ ${state.mode}');
    try {
      final api = ref.read(voiceApiProvider);
      // 1) Micro + kết nối WebRTC
      final mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      _mic = mic;
      _log('đã có micro');
      final pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      _pc = pc;
      for (final t in mic.getAudioTracks()) {
        await pc.addTrack(t, mic);
      }
      pc.onTrack = (e) => _log('nhận track ${e.track.kind}');
      pc.onConnectionState = (s) => _log('kết nối: $s');
      pc.onIceConnectionState = (s) => _log('ice: $s');
      // Kênh sự kiện phải tạo trước khi tạo offer.
      final dc = await pc.createDataChannel('oai-events', RTCDataChannelInit()..ordered = true);
      _dc = dc;
      dc.onMessage = (m) => _onMessage(m.text);
      dc.onDataChannelState = (s) => _log('kênh dữ liệu: $s');

      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      await _waitIce(pc);
      final local = await pc.getLocalDescription();
      final sdp = local?.sdp;
      if (sdp == null || sdp.isEmpty) throw StateError('Không tạo được SDP offer');
      final tOffer = _sw.elapsedMilliseconds;
      _metric('offer_ready_ms', '$tOffer');

      // 2) Máy chủ đổi SDP với OpenAI
      final r = await api.liveStart(sdp: sdp, liveMode: state.mode, honorific: _honorific);
      _metric('server_roundtrip_ms', '${_sw.elapsedMilliseconds - tOffer}');
      _metric('server_ms', '${r.serverMs}');
      _log('phiên ${r.sessionId} (chế độ ${r.mode})');
      await pc.setRemoteDescription(RTCSessionDescription(r.sdp, 'answer'));
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      _log('LỖI: $e');
      state = state.copyWith(error: '$e');
      await _teardown();
      state = state.copyWith(phase: LivePhase.idle);
    }
  }

  Future<void> _waitIce(RTCPeerConnection pc) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final done = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) done.complete();
    };
    await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  Future<void> end() async {
    if (state.phase == LivePhase.idle || state.phase == LivePhase.closing) return;
    final dc = _dc;
    if (state.phase == LivePhase.live && dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      state = state.copyWith(phase: LivePhase.closing);
      _send({'type': 'session.close'});
      _closeTimeout = Timer(const Duration(seconds: 15), () {
        _log('không nhận được session.closed, đóng thủ công');
        unawaited(_finish());
      });
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    await _teardown();
    state = state.copyWith(phase: LivePhase.idle);
  }

  Future<void> _teardown() async {
    _flushTimer?.cancel();
    _closeTimeout?.cancel();
    _flushTimer = _closeTimeout = null;
    try {
      _dc?.close();
    } catch (_) {}
    _dc = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _mic?.dispose();
    } catch (_) {}
    _mic = null;
  }

  void _send(Map<String, Object?> e) {
    final dc = _dc;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) return;
    dc.send(RTCDataChannelMessage(jsonEncode(e)));
  }

  String _id() => 'e${++_evt}';

  // ---------- Nhận sự kiện ----------

  void _onMessage(String raw) {
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _log('sự kiện không phải JSON');
      return;
    }
    final type = (e['type'] as String?) ?? '?';
    final now = _sw.elapsedMilliseconds;
    // Chưa biết hết tên sự kiện: ghi lần đầu của mỗi loại (kèm mẫu) để xem lại sau.
    if (_seenTypes.add(type) && type != 'response.event') {
      _log('SỰ KIỆN MỚI $type ${_clip(raw, 260)}');
    }
    switch (type) {
      case 'session.started':
        state = state.copyWith(phase: LivePhase.live);
        _metric('start_to_started_ms', '$now');
        _sendContext();
      case 'session.closed':
        _log('session.closed usage=${jsonEncode(e['usage'])}');
        _metric('usage', jsonEncode(e['usage']));
        unawaited(_finish());
      case 'session.input_transcript.delta':
        _lastUserAt = now;
        _userBuf += (e['delta'] as String?) ?? '';
        state = state.copyWith(userText: _userBuf);
        _awaitingFirstSpeech = true;
      case 'session.output_transcript.delta':
        if (_awaitingFirstSpeech && _lastUserAt >= 0) {
          _awaitingFirstSpeech = false;
          _metric('user_stop_to_first_reply_ms', '${now - _lastUserAt}');
          if (_lastResultAt >= 0) _metric('result_to_speech_ms', '${now - _lastResultAt}');
          _userBuf = '';
        }
        state = state.copyWith(assistantText: state.assistantText + ((e['delta'] as String?) ?? ''));
      case 'session.delegation.created':
        _delegationAt = now;
        if (_lastUserAt >= 0) _metric('user_stop_to_delegation_ms', '${now - _lastUserAt}');
        if (state.mode == 'C') {
          final id = (e['delegation'] as Map?)?['id'] as String?;
          unawaited(_clientDelegate(id));
        }
      case 'response.event':
        _onResponseEvent(e);
      default:
        break;
    }
  }

  void _onResponseEvent(Map<String, dynamic> env) {
    final ev = env['event'];
    if (ev is! Map) return;
    final t = ev['type'] as String?;
    if (t == 'response.output_item.done') {
      final item = ev['item'];
      if (item is Map && item['type'] == 'function_call') {
        final now = _sw.elapsedMilliseconds;
        if (_delegationAt >= 0) _metric('delegation_to_function_ms', '${now - _delegationAt}');
        unawaited(_runFunction(item.cast<String, dynamic>()));
      }
    }
  }

  // ---------- Chế độ R: chạy hàm do Luna chọn ----------

  Future<void> _runFunction(Map<String, dynamic> item) async {
    final name = (item['name'] as String?) ?? '';
    final callId = (item['call_id'] as String?) ?? '';
    Map<String, dynamic> args = {};
    try {
      final a = item['arguments'];
      if (a is String && a.isNotEmpty) args = jsonDecode(a) as Map<String, dynamic>;
    } catch (_) {}
    _log('HÀM $name ${jsonEncode(args)}');
    final out = await _simulate(name, args);
    _pending.add({
      'type': 'response.item.create',
      'event_id': _id(),
      'item': {'type': 'function_call_output', 'call_id': callId, 'output': jsonEncode(out)},
    });
    // Gom các lệnh gọi cùng lượt rồi trả kết quả một lần.
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      for (final p in _pending) {
        _send(p);
      }
      _pending.clear();
      _send({'type': 'response.create', 'event_id': _id()});
      _lastResultAt = _sw.elapsedMilliseconds;
      _awaitingFirstSpeech = true;
      _log('đã trả kết quả hàm + response.create');
    });
  }

  Future<Map<String, Object?>> _simulate(String name, Map<String, dynamic> a) async {
    switch (name) {
      case 'read_bp':
        return {'ok': true, 'text': await _readBp()};
      case 'prepare_message':
        return {
          'ok': true,
          'status': 'needs_confirmation',
          'recipient': a['recipient'],
          'content': a['content'],
          'note': 'Chưa gửi. Ứng dụng sẽ đọc lại và hỏi người dùng xác nhận (thử nghiệm: chưa làm).',
        };
      case 'open_feature' || 'go_back' || 'go_home' || 'show_bp' || 'play_video' || 'video_control':
        return {'ok': true, 'simulated': true, 'note': 'Thử nghiệm: chưa thực sự thực hiện.'};
      default:
        return {'ok': false, 'error': 'unknown_function'};
    }
  }

  Future<String> _readBp() async {
    try {
      final list = await ref.read(bpReadingsProvider.future);
      if (list.isEmpty) return 'Chưa có kết quả đo huyết áp nào.';
      final r = list.reduce((a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b);
      final cat = BpCategory.of(r.systolic, r.diastolic).label;
      final pulse = r.pulse == null ? '' : ', mạch ${r.pulse}';
      return 'Lần đo gần nhất: huyết áp ${r.systolic} trên ${r.diastolic}$pulse. Mức: $cat.';
    } catch (_) {
      return 'Chưa đọc được kết quả huyết áp.';
    }
  }

  // ---------- Chế độ C: tự suy ý định từ phiên âm ----------

  Future<void> _clientDelegate(String? delegationId) async {
    // Chờ một nhịp để phần phiên âm cuối kịp về.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final t = _fold(_userBuf);
    _log('C: phiên âm="$_userBuf"');
    String say;
    if (t.contains('huyet ap') && (t.contains('doc') || t.contains('bao nhieu') || t.contains('gan nhat'))) {
      say = await _readBp();
    } else if (t.contains('huyet ap')) {
      say = 'Dạ, con mở màn huyết áp ạ (thử nghiệm, chưa mở thật).';
    } else if (t.contains('nhan') || t.contains('nhan tin')) {
      say = 'Dạ, $_honorific muốn nhắn cho ai và nhắn gì ạ? (thử nghiệm)';
    } else {
      say = 'Con chưa rõ $_honorific muốn gì, $_honorific nói lại giúp con nhé.';
    }
    _send({
      'type': 'session.commentary.append',
      'event_id': _id(),
      'delegation_id': delegationId,
      'content': say,
    });
    _lastResultAt = _sw.elapsedMilliseconds;
    _awaitingFirstSpeech = true;
    _log('C: gửi commentary: $say');
  }

  /// Nạp ngữ cảnh lúc mở phiên (không nói ra).
  void _sendContext() {
    _send({
      'type': 'session.thinking.append',
      'event_id': _id(),
      'delegation_id': null,
      'content': 'Người dùng được gọi là "$_honorific". Ứng dụng đang ở chế độ thử nghiệm.',
    });
  }

  String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

  static const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  static final _to = '${'a' * 17}${'e' * 11}${'i' * 5}${'o' * 17}${'u' * 11}${'y' * 5}d';

  String _fold(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      final i = _from.indexOf(c);
      b.write(i >= 0 ? _to[i] : c);
    }
    return b.toString();
  }
}

final liveLabProvider = NotifierProvider<LiveLabController, LiveLabState>(LiveLabController.new);
