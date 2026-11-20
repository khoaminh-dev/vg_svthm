import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Ghi nhật ký hoạt động ra file để đọc lại khi thử bằng máy thật (adb pull).
/// CHỈ chạy khi build với `--dart-define=VG_TRACE=true`; bản phát hành thường không ghi gì
/// (nhật ký có thể chứa lời nói và tên người thân, không được bật cho người dùng thật).
const bool kTrace = bool.fromEnvironment('VG_TRACE');

class AppTrace {
  static File? _file;
  static AppLifecycleListener? _life;

  /// File nằm ở `/sdcard/Android/data/<gói>/files/vg_trace.log`.
  static Future<void> init() async {
    if (!kTrace || _file != null) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      _file = File('${dir.path}/vg_trace.log');
      line('=== app khởi động ===');
      _life = AppLifecycleListener(onStateChange: (s) => line('vòng đời app: $s'));
    } catch (_) {
      // không ghi được thì thôi, không ảnh hưởng app
    }
  }

  static void line(String s) {
    final f = _file;
    if (!kTrace || f == null) return;
    try {
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $s\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static void dispose() => _life?.dispose();
}
