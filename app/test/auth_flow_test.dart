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
  void signInGoogleNoProfile() => _set(const AuthUser(id: '2', email: 'g@b.co', fullName: 'Gee'));

  @override
  Future<bool> isUsernameAvailable(String username) async => true;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) async => false;

  @override
  Future<bool> signInWithGoogle() async => true;

  @override
  Future<void> completeProfile({required String username, required String displayName}) async =>
      _set(AuthUser(id: '2', email: 'g@b.co', fullName: displayName, username: username));

  @override
  Future<void> signOut() async => _set(null);
}

/// Trang chủ có quả cầu Vy chuyển động liên tục nên `pumpAndSettle` không bao giờ yên: bơm vài khung hình.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
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
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await repo.signIn(email: 'a@b.co', password: '12345678');
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hôm nay bạn cần gì?'), findsOneWidget);

    await repo.signOut();
    await settle(tester);
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
    await settle(tester);

    repo.signInGoogleNoProfile();
    await settle(tester);
    expect(find.byType(CompleteProfileScreen), findsOneWidget);

    await repo.completeProfile(username: 'gee', displayName: 'Gee');
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
