import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/med_scan_models.dart';

/// Gửi CHỮ đã che thông tin cá nhân (không gửi ảnh) tới `/api/ocr` (chế độ `med_text`) để tách thành lịch thuốc.
class MedScanClient {
  MedScanClient({required this.accessToken, http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final String? Function() accessToken;
  final http.Client _client;
  final String _baseUrl;

  Future<ScanResult> parse(String redactedText) async {
    if (_baseUrl.isEmpty) {
      throw const AppFailure('Chưa cấu hình máy chủ AI');
    }
    final token = accessToken();
    if (token == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_baseUrl/api/ocr'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'mode': 'med_text', 'text': redactedText}),
          )
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw const AppFailure('Không kết nối được máy chủ, hãy kiểm tra mạng');
    }
    if (res.statusCode != 200) {
      throw switch (res.statusCode) {
        401 => const AppFailure('Phiên đăng nhập đã hết hạn, hãy đăng nhập lại'),
        413 => const AppFailure('Đơn dài quá, hãy chụp từng phần'),
        429 => const AppFailure('Thao tác quá nhanh, thử lại sau ít phút'),
        _ => const AppFailure('Dịch vụ đọc đơn đang bận, thử lại sau'),
      };
    }
    try {
      return ScanResult.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const AppFailure('Máy chủ trả về dữ liệu không hợp lệ');
    }
  }
}
