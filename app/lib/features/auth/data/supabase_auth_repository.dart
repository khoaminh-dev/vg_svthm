import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_error_mapper.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;
  Future<void>? _googleInit;

  sb.GoTrueClient get _auth => _client.auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthChange> get changes => _auth.onAuthStateChange.map(
        (s) => AuthChange(
          user: _toUser(s.session?.user),
          passwordRecovery: s.event == sb.AuthChangeEvent.passwordRecovery,
        ),
      );

  @override
  Future<bool> isUsernameAvailable(String username) => _guard(() async {
        final res = await _client.rpc(
          'is_username_available',
          params: {'p_username': username.trim().toLowerCase()},
        );
        return res as bool;
      });

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) =>
      _guard(() async {
        final res = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': fullName.trim(), 'username': username.trim().toLowerCase()},
        );
        return res.session == null;
      });

  @override
  Future<bool> signInWithGoogle() async {
    if (Env.googleWebClientId.isEmpty) {
      throw const AppFailure('Chưa cấu hình GOOGLE_WEB_CLIENT_ID');
    }
    try {
      _googleInit ??= GoogleSignIn.instance.initialize(
        serverClientId: Env.googleWebClientId,
        clientId: Env.googleIosClientId.isEmpty ? null : Env.googleIosClientId,
      );
      await _googleInit;
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppFailure('Không lấy được thông tin từ Google');
      }
      await _auth.signInWithIdToken(provider: sb.OAuthProvider.google, idToken: idToken);
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw const AppFailure('Đăng nhập Google thất bại, vui lòng thử lại');
    } catch (e) {
      throw e is AppFailure ? e : mapAuthError(e);
    }
  }

  @override
  Future<void> completeProfile({
    required String username,
    required String displayName,
  }) =>
      _guard(() async {
        final uid = _auth.currentUser?.id;
        if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
        final name = username.trim().toLowerCase();
        await _client
            .from('profiles')
            .update({'username': name, 'display_name': displayName.trim()})
            .eq('id', uid);
        // Cập nhật metadata để app biết đã hoàn tất hồ sơ (phát sự kiện userUpdated).
        await _auth.updateUser(
          sb.UserAttributes(data: {'username': name, 'full_name': displayName.trim()}),
        );
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(
        () => _auth.resetPasswordForEmail(
          email.trim(),
          redirectTo: Env.resetPasswordRedirect,
        ),
      );

  @override
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _auth.updateUser(sb.UserAttributes(password: newPassword)));

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  AuthUser? _toUser(sb.User? u) => u == null
      ? null
      : AuthUser(
          id: u.id,
          email: u.email,
          fullName: u.userMetadata?['full_name'] as String?,
          username: u.userMetadata?['username'] as String?,
        );

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw e is AppFailure ? e : mapAuthError(e);
    }
  }
}
