import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vg_svthm/features/chat/data/supabase_chat_repository.dart';
import 'package:vg_svthm/features/chat/domain/message.dart';
import 'package:vg_svthm/features/chat/presentation/widgets/message_input.dart';

// PNG 1x1 hợp lệ để ảnh xem trước giải mã được.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  test('Message.fromMap: tin ảnh có chú thích, ảnh không chú thích, ảnh hết hạn', () {
    final base = {'id': 1, 'room_id': 'r', 'user_id': 'u', 'created_at': '2026-01-01T00:00:00Z'};
    final withCaption = Message.fromMap({...base, 'content': 'Đơn thuốc', 'image_path': 'r/u/a.jpg'});
    expect(withCaption.hasImage, isTrue);
    expect(withCaption.content, 'Đơn thuốc');

    final noCaption = Message.fromMap({...base, 'content': '', 'image_path': 'r/u/a.jpg'});
    expect(noCaption.hasImage, isTrue);
    expect(noCaption.content, isEmpty);

    final expired = Message.fromMap({...base, 'content': '', 'image_expired_at': '2026-04-01T00:00:00Z'});
    expect(expired.hasImage, isFalse);
    expect(expired.imageExpired, isTrue);

    final plain = Message.fromMap({...base, 'content': 'xin chào'});
    expect(plain.hasImage, isFalse);
    expect(plain.imageExpired, isFalse);
  });

  test('imageKind nhận dạng theo nội dung, từ chối định dạng lạ', () {
    expect(SupabaseChatRepository.imageKind(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]))?.ext, 'jpg');
    expect(SupabaseChatRepository.imageKind(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]))?.ext, 'png');
    final webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
    expect(SupabaseChatRepository.imageKind(webp)?.ext, 'webp');
    expect(SupabaseChatRepository.imageKind(Uint8List.fromList([1, 2, 3, 4])), isNull);
    // HEIC (ftyp) không được hỗ trợ
    expect(SupabaseChatRepository.imageKind(Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70])), isNull);
  });

  testWidgets('đính kèm ảnh: xem trước, chú thích tùy chọn, gửi không chú thích vẫn được', (tester) async {
    final sent = <(Uint8List, String)>[];
    final bytes = _png;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              onSend: (_) async => true,
              onSendImage: (b, c) async {
                sent.add((b, c));
                return true;
              },
              pickImage: (_) async => XFile.fromData(bytes, name: 'a.jpg'),
            ),
          ),
        ),
      ),
    );

    // Chưa có ảnh: gửi rỗng không làm gì.
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(sent, isEmpty);

    await tester.tap(find.byTooltip('Gửi ảnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget); // ảnh xem trước
    expect(find.text('Thêm chú thích (không bắt buộc)'), findsOneWidget);

    // Gửi ngay không chú thích.
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(sent.single.$2, '');
    expect(find.byType(Image), findsNothing); // đã xóa xem trước

    // Lần 2: có chú thích.
    await tester.tap(find.byTooltip('Gửi ảnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Đơn thuốc mới');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(sent, hasLength(2));
    expect(sent.last.$2, 'Đơn thuốc mới');
  });

  testWidgets('bỏ ảnh đã chọn thì quay về nhắn chữ', (tester) async {
    final texts = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              onSend: (t) async {
                texts.add(t);
                return true;
              },
              onSendImage: (_, _) async => true,
              pickImage: (_) async => XFile.fromData(_png, name: 'a.png'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Gửi ảnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chụp ảnh'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byTooltip('Bỏ ảnh'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);

    await tester.enterText(find.byType(TextField), 'chào');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(texts, ['chào']);
  });
}
