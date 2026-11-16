import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/app.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/auth/presentation/screens/register_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_invite_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/home/presentation/elder_home_screen.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, settle;

Future<FakeAuthRepository> boot(WidgetTester t, {AppRole? role, bool forParent = false}) async {
  final repo = FakeAuthRepository()..startRole = role;
  await t.pumpWidget(ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(repo)], child: const App()));
  await settle(t);
  await repo.signIn(email: 'a@b.co', password: '12345678');
  await settle(t);
  return repo;
}

void main() {
  test('AppRole đọc từ mã', () {
    expect(AppRole.of('elder'), AppRole.elder);
    expect(AppRole.of('family'), AppRole.family);
    expect(AppRole.of(null), isNull);
    expect(AppRole.of('admin'), isNull);
  });

  testWidgets('tài khoản cũ chưa có vai trò: hỏi một lần, chọn sẵn Người cao tuổi, rồi vào trang chủ', (t) async {
    final repo = await boot(t, role: null);
    expect(find.byKey(const Key('choose-role')), findsOneWidget);
    expect(find.text('Bạn là ai?'), findsOneWidget);
    expect(find.byKey(const Key('role-parent')), findsOneWidget, reason: 'lần chọn đầu có lựa chọn cài hộ');
    await t.tap(find.byKey(const Key('role-continue')));
    await settle(t);
    expect(repo.lastRole, AppRole.elder);
    expect(repo.lastForParent, false);
    expect(find.byType(ElderHomeScreen), findsOneWidget);
    // Có vai trò rồi thì không hỏi lại.
    expect(find.byKey(const Key('choose-role')), findsNothing);
  });

  testWidgets('chọn "Tôi chăm sóc người thân" thì vai trò là người thân', (t) async {
    final repo = await boot(t, role: null);
    await t.tap(find.byKey(const Key('role-family')));
    await t.pump();
    await t.tap(find.byKey(const Key('role-continue')));
    await settle(t);
    expect(repo.lastRole, AppRole.family);
  });

  testWidgets('"Tôi cài hộ cho cha mẹ": vai trò người cao tuổi, rồi dẫn tới màn mời người thân một lần', (t) async {
    final repo = await boot(t, role: null);
    await t.tap(find.byKey(const Key('role-parent')));
    await t.pump();
    await t.tap(find.byKey(const Key('role-continue')));
    await settle(t);
    expect(repo.lastRole, AppRole.elder);
    expect(repo.lastForParent, true);
    // Đã tới màn mời (route /family/invite): có nút/ô tạo mã mời.
    expect(find.byType(FamilyInviteScreen), findsOneWidget);
    expect(find.byType(ElderHomeScreen), findsNothing);
  });

  testWidgets('đăng ký: bắt buộc chọn vai trò', (t) async {
    await t.pumpWidget(MaterialApp(home: ProviderScope(child: const RegisterScreen())));
    await t.pump();
    final submit = find.text('Đăng ký').last;
    await t.ensureVisible(submit);
    await t.tap(submit);
    await t.pump();
    expect(find.byKey(const Key('role-missing')), findsOneWidget);
    await t.tap(find.byKey(const Key('role-elder')));
    await t.pump();
    expect(find.byKey(const Key('role-missing')), findsNothing);
  });

  testWidgets('vai trò Người thân thì luôn ở chế độ theo dõi, vai trò Người cao tuổi thì không', (t) async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(const AuthUser(id: 'u', username: 'u', role: AppRole.family)),
    ]);
    addTearDown(c.dispose);
    expect(c.read(watchModeProvider), isTrue);
    final c2 = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(const AuthUser(id: 'u', username: 'u', role: AppRole.elder)),
    ]);
    addTearDown(c2.dispose);
    expect(c2.read(watchModeProvider), isFalse);
  });
}
