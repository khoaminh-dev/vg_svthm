import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/app.dart';
import 'package:vg_svthm/features/auth/domain/auth_repository.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/auth/presentation/screens/complete_profile_screen.dart';
import 'package:vg_svthm/features/auth/presentation/screens/login_screen.dart';
import 'package:vg_svthm/features/home/presentation/elder_home_screen.dart';

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
      _set(AuthUser(id: '1', email: 'a@b.co', fullName: 'An', username: 'an', role: startRole));

  /// Vai trò của tài khoản đăng nhập thử (null = tài khoản cũ chưa chọn vai trò).
  AppRole? startRole = AppRole.elder;
  bool startInstallForParent = false;
  AppRole? lastRole;
  bool? lastForParent;
  int guideCleared = 0;

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
    AppRole? role,
    bool forParent = false,
  }) async => false;

  @override
  Future<void> setRole(AppRole role, {bool forParent = false}) async {
    lastRole = role;
    lastForParent = forParent;
    final u = _user!;
    _set(AuthUser(id: u.id, email: u.email, fullName: u.fullName, username: u.username, role: role, installForParent: forParent));
  }

  @override
  Future<void> clearInstallGuide() async {
    guideCleared++;
    final u = _user;
    if (u != null) _set(AuthUser(id: u.id, email: u.email, fullName: u.fullName, username: u.username, role: u.role));
  }

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
    expect(find.byType(ElderHomeScreen), findsOneWidget);
    expect(find.text('Chạm vào Vy rồi nói'), findsOneWidget);

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
    // Chưa chọn vai trò: hỏi "Bạn là ai?" trước khi vào trang chủ.
    expect(find.byKey(const Key('choose-role')), findsOneWidget);
    await tester.tap(find.byKey(const Key('role-continue')));
    await settle(tester);
    expect(find.byType(ElderHomeScreen), findsOneWidget);
  });
}
