import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repositories.dart';

/// Đọc ảnh bằng AI (Groq vision) qua endpoint `/api/ocr` trên Vercel.
class ApiOcrEngine implements OcrEngine {
  ApiOcrEngine({
    required this.accessToken,
    this.mode,
    http.Client? client,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? Env.apiBaseUrl;

  /// Lấy token đăng nhập hiện tại (Supabase) để API xác thực người dùng.
  final String? Function() accessToken;

  /// `bp` để chỉ đọc SYS/DIA/PULSE (nhanh hơn); null là đọc tổng quát.
  final String? mode;
  final http.Client _client;
  final String _baseUrl;

  @override
  Future<OcrScan> scan(String imagePath) async {
    if (_baseUrl.isEmpty) {
      throw const AppFailure('Chưa cấu hình API_BASE_URL để dùng AI');
    }
    final token = accessToken();
    if (token == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');

    // Ảnh chụp từ camera điện thoại có thể rất lớn (nhiều MB) và bị chặn ở mức ~4,5 MB của máy chủ,
    // nên thu nhỏ về cạnh dài 1280 px, JPEG chất lượng 80 trước khi gửi (đủ để đọc số trên màn hình máy đo).
    var bytes = await XFile(imagePath).readAsBytes();
    var mime = imagePath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    try {
      final small = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (small.isNotEmpty && small.length < bytes.length) {
        bytes = small;
        mime = 'image/jpeg';
      }
    } catch (_) {
      // Không nén được thì gửi ảnh gốc.
    }
    final sizeKb = (bytes.length / 1024).round();

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_baseUrl/api/ocr'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'image': base64Encode(bytes),
              'mime': mime,
              if (mode != null) 'mode': mode,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      // Kèm mã ngắn (loại lỗi, dung lượng ảnh) để biết nguyên nhân khi tester báo lỗi.
      throw AppFailure(
        'Không kết nối được máy chủ AI, hãy kiểm tra mạng (${e.runtimeType}, ${sizeKb}KB)',
      );
    }

    if (res.statusCode != 200) throw _failure(res.statusCode);

    try {
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final values = (json['values'] as List<dynamic>? ?? const [])
          .map((e) => OcrValue.fromJson(e as Map<String, dynamic>))
          .toList();
      return OcrScan(
        rawText: (json['raw_text'] as String?) ?? '',
        values: values,
      );
    } catch (_) {
      throw const AppFailure('Máy chủ AI trả về dữ liệu không hợp lệ');
    }
  }

  AppFailure _failure(int status) => switch (status) {
    401 => const AppFailure('Phiên đăng nhập đã hết hạn, hãy đăng nhập lại'),
    413 => const AppFailure(
      'Ảnh quá lớn, hãy chụp lại ở độ phân giải thấp hơn',
    ),
    429 => const AppFailure('Thao tác quá nhanh, vui lòng thử lại sau ít phút'),
    _ => const AppFailure('Dịch vụ AI đang bận, vui lòng thử lại sau'),
  };
}
