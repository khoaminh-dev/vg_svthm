import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repositories.dart';

class SupabaseOcrRepository implements OcrRepository {
  SupabaseOcrRepository(this._client);

  static const _bucket = 'ocr-images';

  /// Nhận dạng định dạng ảnh theo nội dung file (không tin vào đuôi file).
  static ({String ext, String mime}) sniff(List<int> b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', mime: 'image/png');
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
      return (ext: 'webp', mime: 'image/webp');
    }
    if (at(4, [0x66, 0x74, 0x79, 0x70])) return (ext: 'heic', mime: 'image/heic'); // ftyp
    return (ext: 'jpg', mime: 'image/jpeg');
  }

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    return id;
  }

  @override
  Future<List<OcrRecord>> list({DateTime? before, int limit = 20}) => _guard(() async {
    var q = _client.from('ocr_records').select();
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(OcrRecord.fromMap).toList();
  });

  @override
  Future<OcrRecord> save({
    required String title,
    required String rawText,
    required List<OcrValue> values,
    required String localImagePath,
  }) => _guard(() async {
    final uid = _uid;
    final bytes = await XFile(localImagePath).readAsBytes();
    final kind = sniff(bytes);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.${kind.ext}';
    final path = '$uid/$name';

    await _client.storage
        .from(_bucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: kind.mime));

    try {
      final row = await _client
          .from('ocr_records')
          .insert({
            'user_id': uid,
            'title': title.trim(),
            'raw_text': rawText,
            'values': values.map((v) => v.toJson()).toList(),
            'image_path': path,
          })
          .select()
          .single();
      return OcrRecord.fromMap(row);
    } catch (e) {
      // Không để lại ảnh mồ côi nếu lưu bản ghi thất bại.
      await _client.storage.from(_bucket).remove([path]);
      rethrow;
    }
  });

  @override
  Future<void> delete(OcrRecord record) => _guard(() async {
    // Xoá ảnh trước: nếu bước này lỗi thì bản ghi còn nguyên để thử lại, không để ảnh riêng tư mồ côi.
    final path = record.imagePath;
    if (path != null) await _client.storage.from(_bucket).remove([path]);
    await _client.from('ocr_records').delete().eq('id', record.id);
  });

  @override
  Future<String?> imageUrl(OcrRecord record) async {
    final path = record.imagePath;
    if (path == null) return null;
    try {
      return await _client.storage.from(_bucket).createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Không lưu được, hãy kiểm tra mạng và thử lại');
    }
  }
}
