import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/core/utils/time_format.dart';
import 'package:vg_svthm/features/chat/domain/chat_repository.dart';
import 'package:vg_svthm/features/chat/domain/room.dart';
import 'package:vg_svthm/features/chat/presentation/providers/chat_providers.dart';
import 'package:vg_svthm/features/chat/presentation/screens/room_list_screen.dart';
import 'package:vg_svthm/features/community/presentation/community_providers.dart';
import 'package:vg_svthm/features/community/presentation/community_screen.dart';
import 'package:vg_svthm/shared/models/profile.dart';

class FakeChat implements ChatRepository {
  FakeChat({this.rooms = const [], this.failRooms = false});

  List<Room> rooms;
  bool failRooms;
  int opened = 0;

  @override
  Future<List<Room>> fetchRooms() async {
    if (failRooms) throw Exception('mất mạng');
    return rooms;
  }

  @override
  Stream<void> watchJoinedRooms() => const Stream.empty();

  @override
  Future<Room> openDirectRoom(String username) async {
    opened++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Room(
      id: 'r-$username',
      name: username,
      type: RoomType.direct,
      createdAt: DateTime(2026, 11, 1),
      peer: Profile(id: 'p-$username', username: username),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _people = [
  Profile(id: '1', username: 'lan', displayName: 'Nguyễn Thị Lan'),
  Profile(id: '2', username: 'hung', displayName: 'Hùng'),
  Profile(id: '3', username: 'minh', displayName: 'Minh'),
];

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  test('TimeFormat: giờ ở danh sách và nhãn ngày', () {
    final now = DateTime(2026, 11, 15, 10, 30); // Chủ nhật
    expect(TimeFormat.listTime(DateTime(2026, 11, 15, 9, 5), now), '09:05');
    expect(TimeFormat.listTime(DateTime(2026, 11, 14, 23, 59), now), 'Hôm qua');
    expect(TimeFormat.listTime(DateTime(2026, 11, 12, 8), now), 'Thứ năm');
    expect(TimeFormat.listTime(DateTime(2026, 10, 20, 8), now), '20/10');
    expect(TimeFormat.listTime(DateTime(2025, 10, 20, 8), now), '20/10/2025');
    expect(TimeFormat.dayLabel(DateTime(2026, 11, 15), now), 'Hôm nay');
    expect(TimeFormat.dayLabel(DateTime(2026, 11, 14), now), 'Hôm qua');
    expect(TimeFormat.dayLabel(DateTime(2026, 11, 11), now), 'Thứ tư, 11/11');
    expect(TimeFormat.dayLabel(DateTime(2026, 10, 1), now), '01/10');
    expect(
      TimeFormat.sameDay(
        DateTime(2026, 11, 15, 0, 1),
        DateTime(2026, 11, 15, 23, 59),
      ),
      isTrue,
    );
    expect(
      TimeFormat.sameDay(
        DateTime(2026, 11, 14, 23, 59),
        DateTime(2026, 11, 15, 0, 1),
      ),
      isFalse,
    );
  });

  test('Room.preview: có tin, của mình, có ảnh, chưa có tin', () {
    Room r({
      String? content,
      bool image = false,
      bool mine = false,
      DateTime? at,
    }) => Room(
      id: 'a',
      name: 'x',
      type: RoomType.group,
      createdAt: DateTime(2026),
      lastContent: content,
      lastHasImage: image,
      lastIsMine: mine,
      lastAt: at,
    );
    final at = DateTime(2026, 11, 15);
    expect(r().preview, isNull);
    expect(r(content: 'Chào bác', at: at).preview, 'Chào bác');
    expect(r(content: 'Dạ', mine: true, at: at).preview, 'Bạn: Dạ');
    expect(r(image: true, at: at).preview, 'Đã gửi một ảnh');
    expect(
      r(content: 'Nhìn này', image: true, at: at).preview,
      '[Ảnh] Nhìn này',
    );
  });

  testWidgets(
    'Cộng đồng: tìm kiếm chờ gõ xong mới gọi, rỗng thì báo rõ, xoá được',
    (t) async {
      bigScreen(t);
      var calls = 0;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
            chatRepositoryProvider.overrideWithValue(FakeChat()),
            communityUsersProvider.overrideWith((ref) async {
              calls++;
              final q = ref.watch(communityQueryProvider).toLowerCase();
              return _people
                  .where(
                    (p) =>
                        q.isEmpty ||
                        p.username!.contains(q) ||
                        p.name.toLowerCase().contains(q),
                  )
                  .toList();
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const CommunityScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('3 người dùng'), findsOneWidget);
      expect(find.text('Nguyễn Thị Lan'), findsOneWidget);
      expect(find.text('@lan'), findsOneWidget);
      final before = calls;

      // Gõ từng phím: chưa có cuộc gọi mới cho đến khi dừng gõ.
      await t.enterText(find.byKey(const Key('community-search')), 'l');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byKey(const Key('community-search')), 'la');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byKey(const Key('community-search')), 'lan');
      await t.pump(const Duration(milliseconds: 100));
      expect(calls, before, reason: 'đang gõ thì chưa tìm');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(calls, before + 1, reason: 'dừng gõ thì chỉ tìm đúng một lần');
      expect(find.text('1 kết quả'), findsOneWidget);
      expect(find.text('Hùng'), findsNothing);

      await t.enterText(find.byKey(const Key('community-search')), 'zzz');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text('Không tìm thấy "zzz"'), findsOneWidget);

      await t.tap(find.byKey(const Key('community-clear')));
      await t.pumpAndSettle();
      expect(find.text('3 người dùng'), findsOneWidget);
      expect(find.byKey(const Key('community-clear')), findsNothing);
    },
  );

  testWidgets('Cộng đồng: rời màn rồi mở lại thì không còn từ khoá cũ', (
    t,
  ) async {
    bigScreen(t);
    final show = ValueNotifier(true);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
          chatRepositoryProvider.overrideWithValue(FakeChat()),
          communityUsersProvider.overrideWith((ref) async {
            final q = ref.watch(communityQueryProvider).toLowerCase();
            return _people
                .where((p) => q.isEmpty || p.username!.contains(q))
                .toList();
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, on, _) =>
                on ? const CommunityScreen() : const SizedBox(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('community-search')), 'lan');
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.text('1 kết quả'), findsOneWidget);

    show.value = false;
    await t.pumpAndSettle();
    show.value = true;
    await t.pumpAndSettle();
    expect(
      find.text('3 người dùng'),
      findsOneWidget,
      reason: 'từ khoá cũ phải được xoá',
    );
  });

  testWidgets(
    'Cộng đồng: lỗi mạng có nút Thử lại; bấm Nhắn tin hai lần chỉ mở một phòng',
    (t) async {
      bigScreen(t);
      var fail = true;
      final chat = FakeChat();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CommunityScreen()),
          GoRoute(
            path: '/rooms/:id',
            builder: (_, s) => Text('PHONG ${s.pathParameters['id']}'),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
            chatRepositoryProvider.overrideWithValue(chat),
            communityUsersProvider.overrideWith((ref) async {
              if (fail) throw Exception('mất mạng');
              return _people;
            }),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Chưa tải được danh sách'), findsOneWidget);

      fail = false;
      await t.tap(find.byKey(const Key('community-retry')));
      await t.pumpAndSettle();
      expect(find.text('Chưa tải được danh sách'), findsNothing);
      expect(find.text('Hùng'), findsOneWidget);

      await t.tap(find.byKey(const Key('chat-hung')));
      await t.pump(); // nút đã chuyển sang trạng thái chờ
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byKey(const Key('person-hung')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(
        chat.opened,
        1,
        reason: 'chạm lần hai khi đang mở không được tạo thêm',
      );
      expect(find.text('PHONG r-hung'), findsOneWidget);
    },
  );

  testWidgets(
    'Danh sách phòng: xem trước tin nhắn, giờ, lỗi có nút Thử lại, rỗng có nút hành động',
    (t) async {
      bigScreen(t);
      final now = DateTime.now();
      final chat = FakeChat(
        rooms: [
          Room(
            id: 'a',
            name: 'Gia đình',
            type: RoomType.group,
            createdAt: DateTime(2026, 1, 1),
            lastContent: 'Tối nay ăn cơm nhà nhé',
            lastAt: now,
          ),
          Room(
            id: 'b',
            name: 'x',
            type: RoomType.direct,
            createdAt: DateTime(2026, 1, 1),
            peer: const Profile(id: 'p', username: 'lan', displayName: 'Lan'),
            lastContent: 'Dạ con nhớ rồi',
            lastIsMine: true,
            lastAt: now.subtract(const Duration(days: 1)),
          ),
          Room(
            id: 'c',
            name: 'Phòng mới',
            type: RoomType.group,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      Future<void> open() async {
        await t.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
              chatRepositoryProvider.overrideWithValue(chat),
              communityEnabledProvider.overrideWith((ref) async => false),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const RoomListScreen(),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await open();
      expect(find.text('Tối nay ăn cơm nhà nhé'), findsOneWidget);
      expect(find.text('Bạn: Dạ con nhớ rồi'), findsOneWidget);
      expect(find.text(TimeFormat.hm(now)), findsOneWidget);
      expect(find.text('Hôm qua'), findsOneWidget);
      expect(find.text('Phòng nhóm, chưa có tin nhắn'), findsOneWidget);

      chat.failRooms = true;
      await open();
      expect(find.byKey(const Key('rooms-retry')), findsOneWidget);
      chat.failRooms = false;
      await t.tap(find.byKey(const Key('rooms-retry')));
      await t.pumpAndSettle();
      expect(find.text('Gia đình'), findsOneWidget);

      chat.rooms = [];
      await open();
      expect(find.byKey(const Key('rooms-empty')), findsOneWidget);
      expect(find.byKey(const Key('rooms-empty-direct')), findsOneWidget);
      expect(find.byKey(const Key('rooms-empty-group')), findsOneWidget);
      expect(
        find.byKey(const Key('rooms-empty-community')),
        findsNothing,
        reason: 'cờ cộng đồng tắt thì không mời',
      );
    },
  );
}
