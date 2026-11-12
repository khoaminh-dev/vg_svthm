import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repositories.dart';

class SupabaseOcrRepository implements OcrRepository {
  SupabaseOcrRepository(this._client);

  static const _bucket = 'ocr-images';

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    return id;
  }

  @override
  Future<List<OcrRecord>> list() => _guard(() async {
    final rows = await _client.from('ocr_records').select().order('created_at', ascending: false);
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
    final name = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.jpg';
    final path = '$uid/$name';

    final bytes = await XFile(localImagePath).readAsBytes();
    await _client.storage
        .from(_bucket)
        .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));

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
    await _client.from('ocr_records').delete().eq('id', record.id);
    final path = record.imagePath;
    if (path != null) await _client.storage.from(_bucket).remove([path]);
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
