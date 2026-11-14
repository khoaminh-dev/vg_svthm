import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/health_models.dart';

abstract interface class HealthRepository {
  /// Hồ sơ sức khoẻ của người dùng hiện tại, hoặc null nếu chưa nhập.
  Future<HealthProfile?> getProfile();

  Future<void> saveProfile(HealthProfile profile);

  /// Lần đánh giá gần nhất (đã lưu), hoặc null.
  Future<RiskResult?> latestAssessment();

  /// Nhờ server đánh giá theo hồ sơ và lần đo mới nhất. Null nếu chưa đủ dữ liệu (chưa đo hoặc chưa có hồ sơ).
  Future<RiskResult?> runAssessment();
}

class SupabaseHealthRepository implements HealthRepository {
  SupabaseHealthRepository(this._client, {http.Client? http, String? baseUrl})
    : _http = http ?? _defaultClient(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  static http.Client _defaultClient() => http.Client();

  final SupabaseClient _client;
  final http.Client _http;
  final String _baseUrl;

  @override
  Future<HealthProfile?> getProfile() => _guard(() async {
    final row = await _client.from('health_profile').select().maybeSingle();
    return row == null ? null : HealthProfile.fromMap(row);
  });

  @override
  Future<void> saveProfile(HealthProfile profile) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    await _client.from('health_profile').upsert({
      'user_id': uid,
      ...profile.toUpsert(),
    });
  });

  @override
  Future<RiskResult?> latestAssessment() => _guard(() async {
    final row = await _client
        .from('health_assessments')
        .select('level, details, created_at')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return RiskResult.fromJson(
      row['details'] as Map<String, dynamic>,
      level: row['level'] as String,
      createdAt: row['created_at'] as String,
    );
  });

  @override
  Future<RiskResult?> runAssessment() async {
    final token = _client.auth.currentSession?.accessToken;
    if (_baseUrl.isEmpty || token == null) return null;
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$_baseUrl/api/health-risk'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AppFailure('Chưa đánh giá được, bác kiểm tra mạng nhé');
    }
    if (res.statusCode == 409) return null; // chưa có hồ sơ hoặc chưa có lần đo
    if (res.statusCode != 200)
      throw AppFailure('Chưa đánh giá được (${res.statusCode})');
    return RiskResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw AppFailure('Không đọc/lưu được hồ sơ sức khoẻ (${e.message})');
    } catch (_) {
      throw const AppFailure('Lỗi kết nối, vui lòng thử lại');
    }
  }
}
