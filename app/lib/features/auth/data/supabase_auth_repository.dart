import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/env.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_error_mapper.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;

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
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) =>
      _guard(() async {
        final res = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': fullName.trim()},
        );
        return res.session == null;
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
        );

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapAuthError(e);
    }
  }
}
