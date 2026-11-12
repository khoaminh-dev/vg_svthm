import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/app.dart';
import 'package:vg_svthm/features/auth/domain/auth_repository.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/auth/presentation/screens/complete_profile_screen.dart';
import 'package:vg_svthm/features/auth/presentation/screens/login_screen.dart';
import 'package:vg_svthm/features/home/presentation/home_screen.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthChange>.broadcast();
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthChange> get changes => _controller.stream;

  void _set(AuthUser? user) {
    _user = user;
    _controller.add(AuthChange(user: user));
  }

  @override
  Future<void> signIn({required String email, required String password}) async =>
      _set(const AuthUser(id: '1', email: 'a@b.co', fullName: 'An', username: 'an'));

  /// Mô phỏng tài khoản Google mới: chưa có username.
  void signInGoogleNoProfile() =>
      _set(const AuthUser(id: '2', email: 'g@b.co', fullName: 'Gee'));

  @override
  Future<bool> isUsernameAvailable(String username) async => true;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) async =>
      false;

  @override
  Future<bool> signInWithGoogle() async => true;

  @override
  Future<void> completeProfile({
    required String username,
    required String displayName,
  }) async =>
      _set(AuthUser(id: '2', email: 'g@b.co', fullName: displayName, username: username));

  @override
  Future<void> signOut() async => _set(null);
}

void main() {
  testWidgets('đăng nhập vào trang chủ, đăng xuất về đăng nhập', (tester) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await repo.signIn(email: 'a@b.co', password: '12345678');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('@an'), findsOneWidget);

    await repo.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('tài khoản chưa có username phải hoàn tất hồ sơ', (tester) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    repo.signInGoogleNoProfile();
    await tester.pumpAndSettle();
    expect(find.byType(CompleteProfileScreen), findsOneWidget);

    await repo.completeProfile(username: 'gee', displayName: 'Gee');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
