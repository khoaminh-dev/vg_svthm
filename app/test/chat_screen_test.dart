import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/auth/domain/auth_repository.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/chat/domain/chat_repository.dart';
import 'package:vg_svthm/features/chat/domain/message.dart';
import 'package:vg_svthm/features/chat/domain/room.dart';
import 'package:vg_svthm/features/chat/presentation/providers/chat_providers.dart';
import 'package:vg_svthm/features/chat/presentation/screens/chat_screen.dart';
import 'package:vg_svthm/shared/models/profile.dart';

class _FakeAuth implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'me', username: 'me');
  @override
  Stream<AuthChange> get changes => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeChat implements ChatRepository {
  final _messages = StreamController<List<Message>>.broadcast();
  final _sent = <Message>[];

  @override
  Stream<List<Message>> watchMessages(String roomId) async* {
    yield List.of(_sent);
    yield* _messages.stream;
  }

  @override
  Future<void> sendMessage(String roomId, String content) async {
    _sent.add(Message(
      id: _sent.length + 1,
      roomId: roomId,
      userId: 'me',
      content: content,
      createdAt: DateTime(2026, 1, 1, 9, 5),
    ));
    _messages.add(List.of(_sent));
  }

  void receive(String userId, String content) {
    _sent.add(Message(
      id: _sent.length + 1,
      roomId: 'r1',
      userId: userId,
      content: content,
      createdAt: DateTime(2026, 1, 1, 9, 6),
    ));
    _messages.add(List.of(_sent));
  }

  @override
  Future<List<Profile>> fetchMembers(String roomId) async => const [
        Profile(id: 'me', username: 'me', displayName: 'Tôi'),
        Profile(id: 'u2', username: 'bob', displayName: 'Bob'),
      ];

  @override
  Stream<Set<String>> watchOnline(String roomId) => Stream.value({'me', 'u2'});

  @override
  Future<List<Room>> fetchRooms() async => const [];
  @override
  Future<Room> createRoom(String name) => throw UnimplementedError();
  @override
  Future<void> addMember(String roomId, String username) async {}
}

void main() {
  testWidgets('gửi và nhận tin nhắn realtime', (tester) async {
    final chat = _FakeChat();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(chat),
          authRepositoryProvider.overrideWithValue(_FakeAuth()),
        ],
        child: const MaterialApp(home: ChatScreen(roomId: 'r1', roomName: 'Nhóm A')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhóm A'), findsOneWidget);
    expect(find.text('2 đang online'), findsOneWidget);
    expect(find.textContaining('Chưa có tin nhắn'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'xin chào');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('xin chào'), findsOneWidget);

    chat.receive('u2', 'chào bạn');
    await tester.pumpAndSettle();
    expect(find.text('chào bạn'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
