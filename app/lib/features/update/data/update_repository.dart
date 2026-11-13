import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_update.dart';

/// Giai đoạn tải và cài bản cập nhật.
enum InstallPhase { downloading, installing, failed }

class InstallEvent {
  const InstallEvent(this.phase, {this.progress = 0, this.message});

  final InstallPhase phase;

  /// 0..100, chỉ có nghĩa khi đang tải.
  final int progress;
  final String? message;
}

/// Tải APK và mở trình cài đặt hệ thống. Tách ra để kiểm thử được.
abstract class ApkInstaller {
  Stream<InstallEvent> install(AppUpdate update);
}

const _networkFailure = InstallEvent(
  InstallPhase.failed,
  message: 'Không tải được bản mới, hãy kiểm tra mạng và thử lại.',
);

class OtaApkInstaller implements ApkInstaller {
  @override
  Stream<InstallEvent> install(AppUpdate update) async* {
    try {
      await for (final e in OtaUpdate().execute(
        update.apkUrl,
        destinationFilename: 'viegrand-${update.latestBuild}.apk',
        sha256checksum: update.sha256,
      )) {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            yield InstallEvent(InstallPhase.downloading, progress: int.tryParse(e.value ?? '') ?? 0);
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            yield const InstallEvent(InstallPhase.installing);
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            yield const InstallEvent(
              InstallPhase.failed,
              message: 'Cần cho phép Viegrand cài ứng dụng. Hãy bật quyền trong cài đặt rồi thử lại.',
            );
          case OtaStatus.CHECKSUM_ERROR:
            yield const InstallEvent(InstallPhase.failed, message: 'File tải về bị lỗi, hãy thử lại.');
          case OtaStatus.CANCELED:
            yield const InstallEvent(InstallPhase.failed, message: 'Đã huỷ tải bản cập nhật.');
          case OtaStatus.ALREADY_RUNNING_ERROR:
            break; // đang tải rồi, cứ chờ tiếp
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
          case OtaStatus.INTERNAL_ERROR:
            yield _networkFailure;
        }
      }
    } catch (_) {
      yield _networkFailure;
    }
  }
}

/// Hỏi bảng `app_versions` xem có bản mới hơn bản đang chạy không. Mọi lỗi đều coi như "không có".
class UpdateRepository {
  UpdateRepository(this._client);

  final SupabaseClient _client;

  /// Chỉ Android mới tự cập nhật được (web tự lấy bản mới khi tải lại, iOS không cho cài ngoài App Store).
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdate?> check() async {
    if (!supported) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber);
      if (current == null) return null;
      final row = await _client.from('app_versions').select().eq('platform', 'android').maybeSingle();
      if (row == null) return null;
      return evaluateUpdate(currentBuild: current, row: row);
    } catch (_) {
      return null;
    }
  }
}
