import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/health_models.dart';
import '../../../shared/honorific.dart';

abstract interface class HealthRepository {
  /// Hồ sơ sức khoẻ của người dùng hiện tại, hoặc null nếu chưa nhập.
  Future<HealthProfile?> getProfile({String? ownerId});

  Future<void> saveProfile(HealthProfile profile);

  /// Lần đánh giá gần nhất (đã lưu), hoặc null.
  Future<RiskResult?> latestAssessment({String? ownerId});

  /// Các lần đánh giá gần đây (cũ trước, mới sau) để vẽ xu hướng. [ownerId] null = chính mình.
  Future<List<TrendPoint>> trend({String? ownerId, int limit = 30});

  /// Nhờ server đánh giá theo hồ sơ và lần đo mới nhất. Null nếu chưa đủ dữ liệu (chưa đo hoặc chưa có hồ sơ).
  Future<RiskResult?> runAssessment();

  /// Lịch sử bác hỏi Vy về sức khoẻ, mới nhất trước.
  Future<List<HealthQa>> history();

  Future<void> clearHistory();

  /// Đồng ý tham gia nghiên cứu thử nghiệm: null = chưa hỏi.
  Future<bool?> getResearchConsent();

  /// Bật/tắt. Tắt thì xoá luôn các phản hồi đã gửi.
  Future<void> setResearchConsent(bool value);

  /// Phản hồi đã gửi cho một lần đánh giá, hoặc null.
  Future<RiskFeedback?> getFeedback(String assessmentId);

  Future<void> saveFeedback(
    String assessmentId, {
    required String verdict,
    required String level,
    String? note,
  });
}

class SupabaseHealthRepository implements HealthRepository {
  SupabaseHealthRepository(this._client, {http.Client? http, String? baseUrl})
    : _http = http ?? _defaultClient(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  static http.Client _defaultClient() => http.Client();

  final SupabaseClient _client;
  final http.Client _http;
  final String _baseUrl;

  /// Id người dùng hiện tại. Mọi truy vấn dữ liệu của CHÍNH MÌNH phải lọc theo id này: từ khi có liên kết gia đình,
  /// cơ sở dữ liệu cho phép người chăm sóc đọc thêm dữ liệu của cha mẹ, nên không được dựa vào việc "chỉ trả dữ liệu của mình".
  String _me() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    return id;
  }

  @override
  Future<HealthProfile?> getProfile({String? ownerId}) => _guard(() async {
    final row = await _client
        .from('health_profile')
        .select()
        .eq('user_id', ownerId ?? _me())
        .maybeSingle();
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
  Future<RiskResult?> latestAssessment({String? ownerId}) => _guard(() async {
    final row = await _client
        .from('health_assessments')
        .select('id, level, details, created_at')
        .eq('user_id', ownerId ?? _me())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return RiskResult.fromJson(
      row['details'] as Map<String, dynamic>,
      level: row['level'] as String,
      createdAt: row['created_at'] as String,
      id: row['id'] as String,
    );
  });

  @override
  Future<List<TrendPoint>> trend({String? ownerId, int limit = 30}) =>
      _guard(() async {
        var q = _client
            .from('health_assessments')
            .select('created_at, stroke_p, heart_p, details');
        q = q.eq('user_id', ownerId ?? _me());
        final rows = await q.order('created_at', ascending: false).limit(limit);
        return [for (final r in rows.reversed) TrendPoint.fromRow(r)];
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
      throw AppFailure(hon('Chưa đánh giá được, bác kiểm tra mạng nhé'));
    }
    if (res.statusCode == 409) return null; // chưa có hồ sơ hoặc chưa có lần đo
    if (res.statusCode != 200)
      throw AppFailure('Chưa đánh giá được (${res.statusCode})');
    return RiskResult.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<HealthQa>> history() => _guard(() async {
    final rows = await _client
        .from('health_qa')
        .select('id, question, answer, asked_at')
        .eq('user_id', _me())
        .order('asked_at', ascending: false)
        .limit(100);
    return [for (final r in rows) HealthQa.fromMap(r)];
  });

  @override
  Future<void> clearHistory() => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    await _client.from('health_qa').delete().eq('user_id', uid);
  });

  @override
  Future<bool?> getResearchConsent() => _guard(() async {
    final row = await _client
        .from('health_profile')
        .select('research_consent')
        .eq('user_id', _me())
        .maybeSingle();
    return row?['research_consent'] as bool?;
  });

  @override
  Future<void> setResearchConsent(bool value) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    await _client
        .from('health_profile')
        .update({
          'research_consent': value,
          'research_consent_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', uid);
    if (!value) {
      await _client.from('health_feedback').delete().eq('user_id', uid);
    }
  });

  @override
  Future<RiskFeedback?> getFeedback(String assessmentId) => _guard(() async {
    final row = await _client
        .from('health_feedback')
        .select('verdict, note')
        .eq('assessment_id', assessmentId)
        .maybeSingle();
    return row == null
        ? null
        : RiskFeedback(
            verdict: row['verdict'] as String,
            note: row['note'] as String?,
          );
  });

  @override
  Future<void> saveFeedback(
    String assessmentId, {
    required String verdict,
    required String level,
    String? note,
  }) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    final text = note?.trim() ?? '';
    await _client.from('health_feedback').upsert({
      'user_id': uid,
      'assessment_id': assessmentId,
      'verdict': verdict,
      'level': level,
      'note': text.isEmpty
          ? null
          : (text.length > 300 ? text.substring(0, 300) : text),
    }, onConflict: 'user_id,assessment_id');
  });

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
