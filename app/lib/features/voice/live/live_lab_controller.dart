import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/diagnostics/app_trace.dart';
import '../data/speech_player.dart';
import '../data/voice_actions.dart';
import '../data/voice_api.dart';
import '../domain/voice_models.dart';
import '../core/vy_card.dart';
import '../core/vy_context.dart';
import '../presentation/voice_controller.dart';
import 'live_hybrid.dart';
import 'live_state.dart';

/// Đợt A (thử nghiệm nội bộ) của Vy Live. Xem docs/PREMIUM_LIVE_DESIGN.md.
///
/// Chế độ R: OpenAI chọn hàm (Luna). Các hàm điều hướng/video/nhắn tin vẫn chỉ GIẢ LẬP; `read_bp` đọc thật.
/// Chế độ C (kiểu lai): GPT-Live lo giọng nói; câu lệnh đi qua Vy cũ (`/api/voice/turn` đường chữ) để chọn hàm,
/// rồi chạy bằng `VoiceActions` dùng chung với Vy thường. Bộ xác nhận gửi tin là mã Dart (`ConfirmGate`).

enum LivePhase { idle, connecting, live, closing }

/// Trần một phiên thử (giây). Đợt C sẽ chuyển trần này sang máy chủ (`live_max_session_sec`).
const _maxSessionSec = 240;

class LiveLabState {
  const LiveLabState({
    this.phase = LivePhase.idle,
    this.mode = 'R',
    this.userText = '',
    this.assistantText = '',
    this.metrics = const {},
    this.log = const [],
    this.error,
    this.execReal = true,
    this.sendReal = false,
    this.autoSend = true,
    this.confirmSay,
    this.confirmChips = const [],
    this.emergency = false,
  });

  final LivePhase phase;
  final String mode;
  final String userText;
  final String assistantText;
  final Map<String, String> metrics;
  final List<String> log;
  final String? error;

  /// Thực hiện thật các lệnh mở màn hình/đọc huyết áp/video (tắt thì chỉ giả lập).
  final bool execReal;

  /// Cho phép GỬI TIN THẬT sau khi xác nhận (mặc định tắt: giả lập, không nhắn nhầm người thân).
  final bool sendReal;

  /// Chủ dự án chọn (20/11/2026): nói xong là gửi ngay, không hỏi xác nhận. Vẫn chặn gửi trùng, chỉ gửi khi đã
  /// khớp đúng một người trong danh bạ và có nội dung, và đọc lại cho người dùng nghe đã gửi cho ai, gửi gì.
  final bool autoSend;

  /// Đang chờ xác nhận gửi tin: câu đã đọc lại và các nút (Gửi/Sửa/Hủy).
  final String? confirmSay;
  final List<String> confirmChips;

  /// Vừa phát hiện lời khẩn cấp: hiện nhắc bấm nút gọi người nhà.
  final bool emergency;

  LiveLabState copyWith({
    LivePhase? phase,
    String? mode,
    String? userText,
    String? assistantText,
    Map<String, String>? metrics,
    List<String>? log,
    Object? error = _keep,
    bool? execReal,
    bool? sendReal,
    bool? autoSend,
    Object? confirmSay = _keep,
    List<String>? confirmChips,
    bool? emergency,
  }) => LiveLabState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    userText: userText ?? this.userText,
    assistantText: assistantText ?? this.assistantText,
    metrics: metrics ?? this.metrics,
    log: log ?? this.log,
    error: identical(error, _keep) ? this.error : error as String?,
    execReal: execReal ?? this.execReal,
    sendReal: sendReal ?? this.sendReal,
    autoSend: autoSend ?? this.autoSend,
    confirmSay: identical(confirmSay, _keep) ? this.confirmSay : confirmSay as String?,
    confirmChips: confirmChips ?? this.confirmChips,
    emergency: emergency ?? this.emergency,
  );
}

const _keep = Object();

class LiveLabController extends Notifier<LiveLabState> {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;
  MediaStreamTrack? _remoteAudio; // giọng Live nhận về
  Timer? _flushTimer;
  Timer? _closeTimeout;
  Timer? _capTimer;
  Timer? _fidelityTimer;
  AppLifecycleListener? _lifecycle;
  SpeechPlayer? _player;
  final _sw = Stopwatch();
  int _evt = 0;
  String _honorific = 'bác';
  String _liveSessionId = '';

  // Số đo độ trễ (ms trên đồng hồ _sw).
  int _lastUserAt = -1;
  int _delegationAt = -1;
  int _lastResultAt = -1;
  bool _awaitingFirstSpeech = false;
  final _user = TranscriptBuffer();
  final _pending = <Map<String, Object?>>[];
  final _seenTypes = <String>{};

  // Chế độ C (lai).
  final _gate = ConfirmGate();
  VoiceDialog _dialog = const VoiceDialog();
  List<VoiceContact> _contacts = const [];
  int _turnNo = 0;
  int _seq = 0; // tăng mỗi lượt để bỏ kết quả của lượt cũ
  String? _pendingFingerprint;
  String _lastSay = '';
  String _lastSayClass = 'static';
  String _expectSay = '';
  String _heard = '';
  String _endReason = '';
  bool _collecting = false; // đang chờ phiên âm của một lệnh ủy quyền: đừng bỏ chữ
  DateTime? _dialogAt; // lúc Vy cũ mở một câu hỏi/xác nhận dở dang

  /// Câu hỏi/xác nhận dở dang quá lâu thì bỏ, để câu nói không liên quan không bị hiểu là trả lời nó.
  static const _dialogTtl = Duration(seconds: 45);

  VoiceActions get _actions => ref.read(voiceActionsProvider);

  @override
  LiveLabState build() {
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (state.phase != LivePhase.idle) _log('vòng đời app: $s');
        // Phiên Live tính tiền theo giây: app xuống nền là kết thúc.
        if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) {
          if (state.phase != LivePhase.idle) {
            _endReason = 'app xuống nền ($s)';
            _log('app xuống nền → kết thúc phiên');
            unawaited(end());
          }
        }
      },
    );
    ref.onDispose(() {
      _endReason = 'provider bị hủy (rời màn/đóng app)';
      // Không ghi `state` hay đụng provider khác khi đang huỷ (Riverpod cấm): chỉ ghi vết.
      AppTrace.line('LIVE provider bị hủy');
      _lifecycle?.dispose();
      unawaited(_teardown());
    });
    return const LiveLabState();
  }

  void setMode(String m) {
    if (state.phase == LivePhase.idle) state = state.copyWith(mode: m);
  }

  void setExecReal(bool v) => state = state.copyWith(execReal: v);
  void setSendReal(bool v) => state = state.copyWith(sendReal: v);
  void setAutoSend(bool v) => state = state.copyWith(autoSend: v);

  void _log(String s) {
    final line = '${_sw.isRunning ? _sw.elapsedMilliseconds : 0}ms  $s';
    AppTrace.line('LIVE $line'); // chỉ ghi khi build thử với VG_TRACE (xem app_trace.dart)
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
    final vy = ref.read(voiceControllerProvider);
    if (vy.status != VoiceStatus.idle || vy.panelOpen) {
      state = state.copyWith(error: 'Vy thường đang mở, hãy đóng Vy thường trước khi thử Live.');
      return;
    }
    _sw
      ..reset()
      ..start();
    _evt = 0;
    _lastUserAt = _delegationAt = _lastResultAt = -1;
    _awaitingFirstSpeech = false;
    _user.take();
    _pending.clear();
    _seenTypes.clear();
    _gate.clear();
    _dialog = const VoiceDialog();
    _turnNo = 0;
    _seq = 0;
    _pendingFingerprint = null;
    _lastSay = '';
    _expectSay = _heard = '';
    _endReason = '';
    _dialogAt = null;
    state = LiveLabState(
      phase: LivePhase.connecting,
      mode: state.mode,
      execReal: state.execReal,
      sendReal: state.sendReal,
      autoSend: state.autoSend,
      log: const [],
    );
    ref.read(liveActiveProvider.notifier).set(true);
    _log('bắt đầu, chế độ ${state.mode}, thực thi thật=${state.execReal}, gửi tin thật=${state.sendReal}, tự gửi=${state.autoSend}');
    try {
      final api = ref.read(voiceApiProvider);
      // Cách xưng hô và danh bạ nạp song song với việc mở micro để không kéo dài thời gian kết nối.
      final prep = Future.wait([_actions.loadHonorific(), _actions.contacts()]);
      // 1) Micro + kết nối WebRTC
      final mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      _mic = mic;
      _log('đã có micro');
      final pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      _pc = pc;
      for (final t in mic.getAudioTracks()) {
        await pc.addTrack(t, mic);
      }
      pc.onTrack = (e) {
        _log('nhận track ${e.track.kind}');
        if (e.track.kind == 'audio') _remoteAudio = e.track;
      };
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
      final p = await prep;
      _honorific = p[0] as String;
      _contacts = p[1] as List<VoiceContact>;
      _log('xưng hô "$_honorific", danh bạ ${_contacts.length} phòng');

      // 2) Máy chủ đổi SDP với OpenAI
      final r = await api.liveStart(sdp: sdp, liveMode: state.mode, honorific: _honorific);
      _liveSessionId = r.sessionId;
      _metric('server_roundtrip_ms', '${_sw.elapsedMilliseconds - tOffer}');
      _metric('server_ms', '${r.serverMs}');
      _metric('ack_delay_ms', '${r.ackMs}');
      _log('phiên ${r.sessionId} (chế độ ${r.mode})');
      // Trong lúc chờ máy chủ, kết nối có thể đã bị đóng (rời màn, bấm Kết thúc, app xuống nền...):
      // đừng gắn câu trả lời vào kết nối đã chết, báo rõ lý do.
      if (_pc != pc) {
        throw StateError('Phiên bị đóng trong lúc chờ máy chủ (${_endReason.isEmpty ? 'không rõ lý do' : _endReason})');
      }
      await pc.setRemoteDescription(RTCSessionDescription(r.sdp, 'answer'));
      await Helper.setSpeakerphoneOn(true);
      _capTimer = Timer(const Duration(seconds: _maxSessionSec), () {
        _endReason = 'hết trần $_maxSessionSec giây';
        _log('hết trần $_maxSessionSec giây → kết thúc');
        unawaited(end());
      });
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
    if (_endReason.isEmpty) _endReason = 'người dùng bấm Kết thúc';
    _log('kết thúc phiên: $_endReason');
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
    state = state.copyWith(phase: LivePhase.idle, confirmSay: null, confirmChips: const [], emergency: false);
  }

  Future<void> _teardown() async {
    _flushTimer?.cancel();
    _closeTimeout?.cancel();
    _capTimer?.cancel();
    _fidelityTimer?.cancel();
    _flushTimer = _closeTimeout = _capTimer = _fidelityTimer = null;
    _seq++; // bỏ mọi kết quả đang chờ
    _gate.clear();
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
    _remoteAudio = null;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      ref.read(liveActiveProvider.notifier).set(false);
    } catch (_) {
      // Đang huỷ provider: cờ sẽ tự về mặc định.
    }
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
    AppTrace.line('SỰ KIỆN ${now}ms ${_clip(raw, 400)}');
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
        _user.add((e['delta'] as String?) ?? '', now);
        state = state.copyWith(userText: _user.text);
        _awaitingFirstSpeech = true;
      case 'session.output_transcript.delta':
        final d = (e['delta'] as String?) ?? '';
        // Chế độ C: Live tự trả lời một câu (chào hỏi...) mà không ủy quyền thì câu người dùng đó đã xong.
        // Phải bỏ phiên âm đi, nếu không nó dính vào đầu lệnh kế tiếp ("Con có thể làm gì Nhắn tin cho Giang...").
        // Chỉ bỏ khi người dùng đã im > 700 ms để không cắt ngang một câu đang nói dở.
        if (state.mode == 'C' &&
            !_collecting &&
            !_user.isEmpty &&
            _delegationAt < _lastUserAt &&
            _user.lastChangeMs >= 0 &&
            now - _user.lastChangeMs > 700) {
          _log('bỏ phiên âm câu Live tự trả lời: "${_user.text}"');
          _user.take();
        }
        if (_awaitingFirstSpeech && _lastUserAt >= 0) {
          _awaitingFirstSpeech = false;
          _metric('user_stop_to_first_reply_ms', '${now - _lastUserAt}');
          if (_lastResultAt >= 0) _metric('result_to_speech_ms', '${now - _lastResultAt}');
          if (state.mode != 'C') _user.take(); // chế độ C lấy chữ ở _stableTranscript
        }
        if (_expectSay.isNotEmpty) _heard += d;
        state = state.copyWith(assistantText: state.assistantText + d);
      case 'session.delegation.created':
        _delegationAt = now;
        if (_lastUserAt >= 0) _metric('user_stop_to_delegation_ms', '${now - _lastUserAt}');
        if (state.mode == 'C') {
          final id = ((e['delegation'] as Map?)?['id'] ?? e['delegation_id']) as String?;
          // Báo ngay là đang xử lý để Live không tự chen câu đệm ("để con hỏi lại một chút ạ") lên trước câu trả lời thật.
          if (id != null) {
            _send({
              'type': 'session.thinking.append',
              'event_id': _id(),
              'delegation_id': id,
              'content': 'Đang xử lý, chưa có lời nào cần nói. Hãy giữ im lặng.',
            });
          }
          unawaited(_hybridTurn(id));
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
        return {'ok': true, 'text': await _actions.readBp(_honorific)};
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

  // ---------- Chế độ C (lai): giọng GPT-Live, não Vy cũ ----------

  /// Một lượt: Live báo có việc cần ủy quyền → lấy phiên âm → hỏi Vy cũ → chạy lệnh → trả lời qua Live.
  Future<void> _hybridTurn(String? delegationId) async {
    final seq = ++_seq;
    _collecting = true;
    final String text;
    try {
      text = await _stableTranscript();
    } finally {
      _collecting = false;
    }
    if (seq != _seq) {
      _silentClose(delegationId, 'lượt cũ bị thay bằng lượt mới');
      return;
    }
    _log('C: phiên âm="$text"');
    if (text.isEmpty) {
      await _deliver('Con chưa nghe rõ, $_honorific nói lại giúp con nhé.', 'static', delegationId, seq);
      return;
    }
    // Khẩn cấp: dò ngay trong app, không chờ máy chủ. Câu đọc bằng giọng máy (nguyên văn), không qua Live.
    if (looksLikeEmergency(text)) {
      state = state.copyWith(emergency: true);
      _log('KHẨN CẤP (dò trong app)');
      _dialog = const VoiceDialog();
      _gate.clear();
      state = state.copyWith(confirmSay: null, confirmChips: const []);
      await _deliver(
        '${_cap(_honorific)} hãy bấm nút gọi người nhà hoặc gọi 115 ngay nhé. Nếu thấy nguy hiểm, đừng chờ ạ.',
        'emergency',
        delegationId,
        seq,
      );
      return;
    }
    // Đang chờ xác nhận gửi tin mà người dùng nói cả câu ("bấm gửi cho bác luôn đi"): coi như bấm đúng nút.
    var toBrain = text;
    if (_gate.pending) {
      final chip = classifyConfirmReply(text);
      if (chip != null) {
        _log('C: "$text" → coi như bấm nút "$chip"');
        toBrain = chip;
      }
    }
    await _askBrain(toBrain, delegationId, seq);
  }

  /// Chờ phiên âm ổn định: có chữ và 150 ms không đổi, tối đa 1,2 giây.
  Future<String> _stableTranscript() async {
    final t0 = _sw.elapsedMilliseconds;
    while (_sw.elapsedMilliseconds - t0 < 1200) {
      final quiet = _user.lastChangeMs >= 0 && _sw.elapsedMilliseconds - _user.lastChangeMs >= 150;
      if (!_user.isEmpty && quiet) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final wait = _sw.elapsedMilliseconds - t0;
    _metric('transcript_wait_ms', '$wait');
    return _user.take();
  }

  /// Bấm nút trên màn hình (Gửi/Sửa/Hủy): coi như người dùng vừa nói chữ đó, đi cùng đường với lời nói.
  Future<void> tapChip(String chip) async {
    if (state.mode != 'C' || state.phase != LivePhase.live) return;
    final seq = ++_seq;
    _log('bấm nút "$chip"');
    await _askBrain(chip, null, seq);
  }

  Future<void> _askBrain(String text, String? delegationId, int seq) async {
    final api = ref.read(voiceApiProvider);
    // Câu hỏi/xác nhận bỏ dở quá lâu thì quên đi (nếu không, câu nói không liên quan sẽ bị hiểu là trả lời nó).
    final at = _dialogAt;
    if (at != null && DateTime.now().difference(at) > _dialogTtl) {
      _log('bỏ ngữ cảnh hội thoại cũ (quá ${_dialogTtl.inSeconds}s)');
      _dialog = const VoiceDialog();
      _dialogAt = null;
      _gate.clear();
      state = state.copyWith(confirmSay: null, confirmChips: const []);
    }
    _turnNo++;
    final t0 = _sw.elapsedMilliseconds;
    _log('NÃO HỎI: "$text" (màn=${_actions.screenName()}, đang chờ=${_dialog.pending ?? '-'})');
    final VoiceTurnResult res;
    try {
      res = await api.turn(
        sessionId: 'live_$_liveSessionId',
        turnNo: _turnNo,
        text: text,
        dialog: _dialog,
        screen: _actions.screenName(),
        roomId: _actions.currentRoomId(),
        contacts: _contacts,
        honorific: _honorific,
        uiContext: ref.read(vyUiContextProvider)(),
      );
    } on VoiceApiException catch (e) {
      _log('NÃO LỖI ${e.code}: ${e.message}');
      if (seq != _seq) return _silentClose(delegationId, 'bỏ kết quả lỗi cũ');
      await _deliver('Con đang trục trặc một chút, $_honorific thử lại sau nhé.', 'static', delegationId, seq);
      return;
    }
    final ms = _sw.elapsedMilliseconds - t0;
    _metric('brain_ms', '$ms');
    _log('NÃO ${res.timings.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
    final dd = res.decision;
    _log(
      'NÃO TRẢ: action=${dd.action} lớp=${dd.sayClass} task=${dd.task?.intent ?? '-'} '
      'slots=${jsonEncode(dd.task?.slots ?? const {})} chips=${dd.chips} nói="${_clip(dd.say, 160)}"',
    );
    if (seq != _seq) return _silentClose(delegationId, 'bỏ kết quả cũ');
    await _applyDecision(res.decision, delegationId, seq);
  }

  String _fingerprint(VoiceTask t) => '${t.intent}|${t.slots['room_id'] ?? ''}|${t.slots['content'] ?? ''}';

  Future<void> _applyDecision(VoiceDecision d, String? delegationId, int seq) async {
    var say = d.say;
    var cls = d.sayClass;
    var dialog = const VoiceDialog();
    switch (d.action) {
      case 'confirm':
        final task = d.task;
        if (state.autoSend && _canAutoSend(task)) {
          // Chủ dự án không cần bước xác nhận: gửi ngay rồi đọc lại đã gửi cho ai, gửi gì (qua giọng Live, không giọng máy).
          _gate.clear();
          state = state.copyWith(confirmSay: null, confirmChips: const []);
          // Thật: hiện thẻ tên người nhận + đếm ngược rồi tự gửi (Huỷ được). Thử nghiệm: giả lập như cũ.
          say = state.sendReal ? _actions.startSend(task!, _honorific) : await _sendNow(task!);
          cls = 'static';
          break;
        }
        if (task != null) {
          _pendingFingerprint = _fingerprint(task);
          final code = _gate.issue(_pendingFingerprint!);
          _log('xác nhận: mở cổng $code cho ${task.intent}');
        }
        dialog = VoiceDialog(
          task: d.task,
          pending: d.pending,
          expects: d.expects,
          choices: d.choices,
          aliasPhrase: d.aliasPhrase,
        );
        state = state.copyWith(confirmSay: say, confirmChips: d.chips);
        cls = 'important'; // đọc lại nội dung tin phải nguyên văn
      case 'ask':
        dialog = VoiceDialog(
          task: d.task,
          pending: d.pending,
          expects: d.expects,
          choices: d.choices,
          aliasPhrase: d.aliasPhrase,
        );
        state = state.copyWith(confirmSay: null, confirmChips: const []);
      case 'repeat':
        say = _lastSay.isEmpty ? 'Con chưa nói gì để nhắc lại ạ.' : _lastSay;
        cls = _lastSayClass;
        dialog = _dialog;
      case 'execute':
        state = state.copyWith(confirmSay: null, confirmChips: const []);
        say = await _executeGated(d, say);
      default:
        // cancel | answer | unsupported
        if (d.action == 'cancel') ref.read(vyCardProvider.notifier).clear(); // gỡ thẻ đếm ngược (gọi điện, SOS)
        _gate.clear();
        state = state.copyWith(confirmSay: null, confirmChips: const []);
    }
    _dialog = dialog;
    _dialogAt = (dialog.task != null || dialog.pending != null) ? DateTime.now() : null;
    _lastSay = say;
    _lastSayClass = cls;
    await _deliver(say, cls, delegationId, seq);
  }

  /// Chỉ tự gửi khi đã khớp đúng một người/nhóm trong danh bạ (có room_id) và có nội dung. Còn lại vẫn hỏi như cũ.
  bool _canAutoSend(VoiceTask? t) =>
      t != null &&
      t.intent == 'send_message' &&
      (t.slots['room_id'] ?? '').isNotEmpty &&
      (t.slots['content'] ?? '').trim().isNotEmpty;

  /// Gửi ngay (không hỏi xác nhận) và trả câu đọc lại cho người dùng. Vẫn chặn gửi trùng trong 2 phút.
  Future<String> _sendNow(VoiceTask task) async {
    final name = task.slots['recipient_name'] ?? 'người đó';
    final content = (task.slots['content'] ?? '').trim();
    final fp = _fingerprint(task);
    if (!_gate.firstSend(fp)) {
      _log('CHẶN gửi tin trùng (tự gửi)');
      return 'Tin này con vừa gửi rồi ạ.';
    }
    if (!state.sendReal) {
      _log('TỰ GỬI (GIẢ LẬP) tới $name: "$content"');
      return 'Dạ, con đã nhắn cho $name: $content. (Thử nghiệm: chưa gửi thật.)';
    }
    _log('TỰ GỬI tới $name: "$content"');
    final out = await _actions.execute(task, _contacts, _honorific);
    _log('KẾT QUẢ gửi tin: ${out ?? 'ok'}');
    return out ?? 'Dạ, con đã nhắn cho $name: $content.';
  }

  /// Chạy lệnh nếu được phép. Gửi tin chỉ chạy khi cổng xác nhận đang mở đúng cho nội dung đó.
  Future<String> _executeGated(VoiceDecision d, String say) async {
    final task = d.task;
    if (task == null) return say;
    if (task.intent == 'send_message') {
      final fp = _fingerprint(task);
      if (!_gate.consume(fp)) {
        _log('CHẶN gửi tin: không có xác nhận hợp lệ cho nội dung này');
        return 'Con chưa gửi. ${_cap(_honorific)} nói lại tin nhắn để con xác nhận trước nhé.';
      }
      if (!_gate.firstSend(fp)) {
        _log('CHẶN gửi tin trùng');
        return 'Tin này con vừa gửi rồi ạ.';
      }
      if (!state.sendReal) {
        _log('GIẢ LẬP gửi tin tới ${task.slots['recipient_name']}');
        return 'Dạ, con gửi rồi ạ. (Thử nghiệm: chưa gửi thật.)';
      }
    } else if (!state.execReal) {
      _log('GIẢ LẬP ${task.intent} ${jsonEncode(task.slots)}');
      return say.isEmpty ? 'Dạ, con mở rồi ạ. (Thử nghiệm: chưa thực hiện.)' : say;
    }
    _log('CHẠY ${task.intent} ${jsonEncode(task.slots)}');
    final out = await _actions.execute(task, _contacts, _honorific);
    _log('KẾT QUẢ ${task.intent}: ${out == null ? '(không có lời, dùng câu của não)' : _clip(out, 160)}');
    return out ?? _sayFor(task.intent, say);
  }

  /// Câu não trả cho mọi lệnh chạy xong đều là "con mở rồi ạ" (kể cả "quay lại"): nói đúng việc đã làm.
  String _sayFor(String intent, String fallback) {
    return switch (intent) {
      'go_back' => 'Dạ, con quay lại rồi ạ.',
      'go_home' => 'Dạ, con về trang chủ rồi ạ.',
      'show_bp' => 'Dạ, con mở màn hình huyết áp rồi ạ.',
      _ => fallback,
    };
  }

  /// Nói câu trả lời. Câu khẩn cấp/quan trọng đọc bằng giọng máy (nguyên văn); còn lại qua Live.
  Future<void> _deliver(String say, String cls, String? delegationId, int seq) async {
    if (seq != _seq || say.trim().isEmpty) {
      if (say.trim().isEmpty) _silentClose(delegationId, 'không có gì để nói');
      return;
    }
    state = state.copyWith(assistantText: '');
    final local = cls == 'emergency' || cls == 'important' || delegationId == null;
    _lastResultAt = _sw.elapsedMilliseconds;
    if (local) {
      _log('NÓI (giọng máy, $cls): $say');
      _silentClose(delegationId, 'đã nói bằng giọng máy');
      await _speakLocal(say, cls);
      return;
    }
    _expectSay = say;
    _heard = '';
    _awaitingFirstSpeech = true;
    _send({
      'type': 'session.commentary.append',
      'event_id': _id(),
      'delegation_id': delegationId,
      'content': say,
    });
    _log('NÓI (qua Live, $cls): $say');
    // Sau vài giây so câu ta bảo nói với câu Live thực sự nói.
    _fidelityTimer?.cancel();
    _fidelityTimer = Timer(const Duration(seconds: 6), () {
      if (_expectSay.isEmpty) return;
      final f = sayFidelity(_expectSay, _heard);
      _metric('say_fidelity', f.toStringAsFixed(2));
      _log('ĐỌC LẠI: bảo="$_expectSay" nghe="${_clip(_heard, 200)}"');
      _expectSay = '';
    });
  }

  /// Báo cho Live biết đã xong mà không nói gì (đóng ủy quyền trong im lặng).
  void _silentClose(String? delegationId, String why) {
    if (delegationId == null) return;
    _send({
      'type': 'session.thinking.append',
      'event_id': _id(),
      'delegation_id': delegationId,
      'content': 'Không cần nói gì thêm.',
    });
    _log('đóng ủy quyền trong im lặng ($why)');
  }

  /// Đọc bằng giọng máy; tắt micro trong lúc đọc để Live không nghe lại chính mình.
  Future<void> _speakLocal(String say, String cls) async {
    final tracks = _mic?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final t in tracks) {
      t.enabled = false;
    }
    // Tắt tiếng luôn cả giọng Live: nếu Live đang tự nói (lời đệm...) thì hai giọng sẽ chồng nhau (lỗi đo 20/11).
    final remote = _remoteAudio;
    remote?.enabled = false;
    try {
      final p = _player ??= SpeechPlayer(ref.read(voiceApiProvider));
      await p.speak(say, sayClass: cls);
    } finally {
      for (final t in tracks) {
        t.enabled = true;
      }
      remote?.enabled = true;
    }
  }

  /// Nạp ngữ cảnh lúc mở phiên (không nói ra): cách xưng hô, vài tên trong danh bạ, số đo gần nhất.
  Future<void> _sendContext() async {
    final names = _contacts.take(12).map((c) => c.name).join(', ');
    String bp = '';
    if (state.mode == 'C') {
      try {
        bp = ' ${await _actions.readBp(_honorific)}';
      } catch (_) {}
    }
    _send({
      'type': 'session.thinking.append',
      'event_id': _id(),
      'delegation_id': null,
      'content':
          'Người dùng được gọi là "$_honorific". '
          '${names.isEmpty ? '' : 'Danh bạ có: $names. '}'
          'Ứng dụng đang ở chế độ thử nghiệm.$bp',
    });
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
}

final liveLabProvider = NotifierProvider<LiveLabController, LiveLabState>(LiveLabController.new);
