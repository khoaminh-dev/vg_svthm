/// Mức độ cập nhật: nhắc nhẹ (bỏ qua được) hay bắt buộc (chặn dùng app).
enum UpdateLevel { optional, required }

/// Thông tin một bản cập nhật mới hơn bản đang chạy.
class AppUpdate {
  const AppUpdate({
    required this.latestBuild,
    required this.latestName,
    required this.apkUrl,
    required this.level,
    this.sha256,
    this.notes = '',
  });

  final int latestBuild;
  final String latestName;
  final String apkUrl;
  final String? sha256;
  final String notes;
  final UpdateLevel level;

  bool get isRequired => level == UpdateLevel.required;
}

/// So bản đang chạy ([currentBuild] = versionCode) với dòng trong bảng `app_versions`.
/// Trả null khi đã mới nhất, hoặc dữ liệu không dùng được (không có link https để tải),
/// để tránh khoá người dùng vì cấu hình sai.
AppUpdate? evaluateUpdate({required int currentBuild, required Map<String, dynamic> row}) {
  final latest = row['latest_build'];
  final minBuild = row['min_supported_build'];
  final url = row['apk_url'];
  if (latest is! int || url is! String || !url.startsWith('https://')) return null;
  if (currentBuild >= latest) return null;
  final required = minBuild is int && currentBuild < minBuild;
  final sha = row['apk_sha256'];
  return AppUpdate(
    latestBuild: latest,
    latestName: (row['latest_name'] as String?) ?? '',
    apkUrl: url,
    sha256: sha is String && sha.isNotEmpty ? sha : null,
    notes: (row['notes'] as String?) ?? '',
    level: required ? UpdateLevel.required : UpdateLevel.optional,
  );
}
