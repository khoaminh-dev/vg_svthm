import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/chat/presentation/providers/chat_providers.dart';
import 'package:vg_svthm/features/chat/presentation/screens/room_list_screen.dart';
import 'package:vg_svthm/features/community/presentation/community_providers.dart';
import 'package:vg_svthm/features/family/domain/family_models.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/profile/data/phone_repository.dart';
import 'package:vg_svthm/features/voice/data/direct_caller.dart';

import 'community_chat_test.dart' show FakeChat, bigScreen;

class _Phones implements PhoneRepository {
  _Phones(this.byId);
  final Map<String, String> byId;
  @override
  Future<Map<String, String>> ofUsers(Iterable<String> ids) async => {
    for (final i in ids)
      if (byId.containsKey(i)) i: byId[i]!,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _link = FamilyLink(
  linkId: 'l1',
  role: 'owner',
  otherId: 'u-lan',
  otherName: 'Lan',
  otherUsername: 'lan',
  relation: Relation.con,
  perms: const {},
  status: 'active',
  createdAt: DateTime(2026, 11, 1),
);

Future<List<String>> _host(WidgetTester t, Map<String, String> phones) async {
  bigScreen(t);
  final called = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
        chatRepositoryProvider.overrideWithValue(FakeChat()),
        communityEnabledProvider.overrideWith((ref) async => false),
        familyLinksProvider.overrideWith((ref) async => [_link]),
        phoneRepositoryProvider.overrideWithValue(_Phones(phones)),
        directCallProvider.overrideWithValue((n) async => called.add(n)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const RoomListScreen()),
    ),
  );
  await t.pumpAndSettle();
  return called;
}

void main() {
  testWidgets('người lớn tuổi: nút gọi cạnh "Nhắn cho Lan" gọi đúng số (1 chạm)', (t) async {
    final called = await _host(t, {'u-lan': '0912345678'});
    expect(find.byKey(const Key('msg-family-u-lan')), findsOneWidget);
    await t.tap(find.byKey(const Key('call-family-u-lan')));
    await t.pumpAndSettle();
    expect(called, ['0912345678']);
  });

  testWidgets('người thân chưa có số: không gọi, báo rõ', (t) async {
    final called = await _host(t, {});
    await t.tap(find.byKey(const Key('call-family-u-lan')));
    await t.pumpAndSettle();
    expect(called, isEmpty);
    expect(find.textContaining('chưa có số điện thoại'), findsOneWidget);
  });
}
