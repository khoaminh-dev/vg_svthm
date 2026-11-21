import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('Đổi vai trò luôn hỏi lại; bấm Thôi thì đóng hộp và không đi đâu', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(onPressed: () => confirmRoleChange(c), child: const Text('mo')),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('mo'));
    await t.pumpAndSettle();
    expect(find.text('Đổi vai trò?'), findsOneWidget);
    expect(find.byKey(const Key('role-confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('role-cancel')));
    await t.pumpAndSettle();
    expect(find.text('Đổi vai trò?'), findsNothing);
  });
}
