import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordedClip {
  const RecordedClip(this.bytes, this.durationMs, {required this.heardSpeech});
  final Uint8List bytes;
  final int durationMs;
  final bool heardSpeech;
}

/// Ghi âm một câu nói: tự dừng khi người dùng ngừng nói (VAD theo biên độ) hoặc quá giới hạn.
class VoiceRecorder {
  VoiceRecorder();

  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  Completer<RecordedClip?>? _done;
  String? _path;
  DateTime? _startedAt;

  /// Mức ồn (dBFS) coi là có tiếng nói; nền ồn cao hơn thì tự nâng ngưỡng.
  static const _speechDb = -34.0;
  static const _silenceStop = Duration(milliseconds: 1300);
  static const _noSpeechStop = Duration(seconds: 8);
  static const _maxLength = Duration(seconds: 30);

  bool get isRecording => _done != null;

  Future<bool> ensurePermission() => _rec.hasPermission();

  /// Bắt đầu ghi. Future hoàn tất khi dừng (tự động hoặc gọi [stop]); `null` nếu bị huỷ.
  Future<RecordedClip?> record({void Function(double level)? onLevel}) async {
    if (_done != null) return null;
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/vg_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final done = _done = Completer<RecordedClip?>();
    _startedAt = DateTime.now();
    var heard = false;
    DateTime lastVoice = _startedAt!;
    var floor = -60.0;

    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: _path!,
    );
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      final now = DateTime.now();
      final db = a.current.isFinite ? a.current : -90.0;
      // Theo dõi nền ồn thấp nhất gần đây để ngưỡng thích ứng với phòng ồn.
      floor = db < floor ? db : floor + (db - floor) * 0.01;
      final threshold = _speechDb > floor + 14 ? _speechDb : floor + 14;
      onLevel?.call(((db + 60) / 60).clamp(0.0, 1.0));
      if (db > threshold) {
        heard = true;
        _heard = true;
        lastVoice = now;
      }
      final elapsed = now.difference(_startedAt!);
      if (heard && now.difference(lastVoice) > _silenceStop) {
        unawaited(_finish(heard));
      } else if (!heard && elapsed > _noSpeechStop) {
        unawaited(_finish(heard));
      } else if (elapsed > _maxLength) {
        unawaited(_finish(heard));
      }
    });
    return done.future;
  }

  bool _heard = false;

  /// Dừng ghi và trả kết quả cho [record].
  Future<void> stop() => _finish(_heard);

  Future<void> _finish(bool heard) async {
    final done = _done;
    if (done == null || done.isCompleted) return;
    _heard = false;
    await _amp?.cancel();
    _amp = null;
    final started = _startedAt ?? DateTime.now();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    _done = null;
    path ??= _path;
    RecordedClip? clip;
    try {
      if (path != null) {
        final f = File(path);
        if (await f.exists()) {
          clip = RecordedClip(
            await f.readAsBytes(),
            DateTime.now().difference(started).inMilliseconds,
            heardSpeech: heard,
          );
          await f.delete();
        }
      }
    } catch (_) {}
    done.complete(clip);
  }

  Future<void> cancel() async {
    final done = _done;
    if (done == null) return;
    await _amp?.cancel();
    _amp = null;
    try {
      final p = await _rec.stop();
      if (p != null) await File(p).delete();
    } catch (_) {}
    _done = null;
    if (!done.isCompleted) done.complete(null);
  }

  Future<void> dispose() async {
    await cancel();
    await _rec.dispose();
  }
}
