import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../../core/config/env.dart';
import '../domain/detection_data.dart';

/// Một camera trong màn Camera (demo: clip quay sẵn + file toạ độ nhận diện).
class CameraFeed {
  const CameraFeed({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.detectionsUrl,
  });

  final String id;
  final String title;
  final String videoUrl;
  final String detectionsUrl;
}

/// Camera mặc định: clip và JSON nằm trong bucket Storage công khai `camera-demo`
/// (xem `docs/camera_demo/` để biết tên tệp). Đổi clip chỉ cần tải tệp mới lên, không cần phát hành bản mới.
List<CameraFeed> defaultCameraFeeds({String? baseUrl}) {
  final root =
      baseUrl ?? '${Env.supabaseUrl}/storage/v1/object/public/camera-demo';
  CameraFeed feed(String id, String title) => CameraFeed(
    id: id,
    title: title,
    videoUrl: '$root/$id.mp4',
    detectionsUrl: '$root/$id.json',
  );
  return [
    feed('phong_1', 'Phòng 1'),
    feed('phong_2', 'Phòng 2'),
    feed('sanh_tap', 'Sảnh tập'),
  ];
}

/// Bộ phát video, tách khỏi `video_player` để màn hình kiểm thử được mà không cần nền tảng thật.
abstract class CameraPlayer {
  /// Mở nguồn, tắt tiếng, phát lặp. Ném lỗi nếu không tải được.
  Future<void> start();

  /// Vị trí phát hiện tại (giây), đã nội suy giữa các lần nền tảng báo vị trí để khung bám mượt.
  double get seconds;

  /// Rộng/cao của video; 16/9 nếu chưa biết.
  double get aspect;

  Future<void> seek(double seconds);
  Future<void> restart();
  Widget buildView();
  void dispose();
}

class VideoCameraPlayer implements CameraPlayer {
  VideoCameraPlayer(String url)
    : _controller = VideoPlayerController.networkUrl(Uri.parse(url));

  final VideoPlayerController _controller;
  double _lastPos = 0;
  DateTime _lastAt = DateTime.now();

  @override
  Future<void> start() async {
    await _controller.initialize();
    await _controller.setVolume(0);
    await _controller.setLooping(true);
    _controller.addListener(_onValue);
    await _controller.play();
  }

  void _onValue() {
    final p = _controller.value.position.inMilliseconds / 1000.0;
    if (p != _lastPos) {
      _lastPos = p;
      _lastAt = DateTime.now();
    }
  }

  @override
  double get seconds {
    final v = _controller.value;
    if (!v.isInitialized) return 0;
    if (!v.isPlaying) return _lastPos;
    final dt = DateTime.now().difference(_lastAt).inMilliseconds / 1000.0;
    // Nền tảng báo vị trí thưa; chỉ ngoại suy tối đa nửa giây.
    return _lastPos + dt.clamp(0.0, 0.5);
  }

  @override
  double get aspect {
    final a = _controller.value.aspectRatio;
    return a > 0 ? a : 16 / 9;
  }

  @override
  Future<void> seek(double seconds) async {
    _lastPos = seconds;
    _lastAt = DateTime.now();
    await _controller.seekTo(Duration(milliseconds: (seconds * 1000).round()));
  }

  @override
  Future<void> restart() async {
    await seek(0);
    await _controller.play();
  }

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  void dispose() {
    _controller
      ..removeListener(_onValue)
      ..dispose();
  }
}

/// Mở một camera: tạo bộ phát và tải file toạ độ. Tách ra để kiểm thử thay được bằng bản giả.
abstract class CameraBackend {
  CameraPlayer createPlayer(CameraFeed feed);
  Future<DetectionData?> loadDetections(CameraFeed feed);
}

class NetworkCameraBackend implements CameraBackend {
  const NetworkCameraBackend();

  @override
  CameraPlayer createPlayer(CameraFeed feed) => VideoCameraPlayer(feed.videoUrl);

  /// Thiếu file toạ độ hoặc hỏng thì trả null: video vẫn phát, chỉ ẩn lớp nhận diện.
  @override
  Future<DetectionData?> loadDetections(CameraFeed feed) async {
    try {
      final res = await http
          .get(Uri.parse(feed.detectionsUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return DetectionData.parse(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }
}
