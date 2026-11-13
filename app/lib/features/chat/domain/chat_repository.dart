import 'dart:typed_data';

import '../../../shared/models/profile.dart';
import 'message.dart';
import 'room.dart';

abstract interface class ChatRepository {
  Future<List<Room>> fetchRooms();

  /// Tạo phòng nhóm và tự thêm người tạo vào làm thành viên.
  Future<Room> createRoom(String name);

  /// Mở (hoặc tạo nếu chưa có) cuộc trò chuyện riêng với một username.
  Future<Room> openDirectRoom(String username);

  /// Mời người dùng vào phòng nhóm theo username.
  Future<void> addMember(String roomId, String username);

  Future<List<Profile>> fetchMembers(String roomId);

  /// Phát một sự kiện mỗi khi danh sách thành viên của phòng thay đổi.
  Stream<void> watchMembers(String roomId);

  /// Phát một sự kiện mỗi khi mình được thêm vào một phòng mới.
  Stream<void> watchJoinedRooms();

  /// Danh sách tin nhắn của phòng (cũ đến mới), cập nhật realtime.
  Stream<List<Message>> watchMessages(String roomId);

  /// Tin nhắn cũ hơn mốc [before] (cũ đến mới), tối đa [limit] tin. Dùng cho nút "Tải tin cũ hơn".
  Future<List<Message>> fetchOlderMessages(
    String roomId, {
    required DateTime before,
    int limit = 50,
  });

  Future<void> sendMessage(String roomId, String content);

  /// Gửi một ảnh (đã nén) kèm chú thích tùy chọn. Ném [AppFailure] nếu ảnh không hợp lệ hoặc gửi lỗi.
  Future<void> sendImage(String roomId, Uint8List bytes, {String caption = ''});

  /// Đường dẫn tạm (có hạn) để xem ảnh trong chat; null nếu không lấy được.
  Future<String?> imageUrl(String imagePath);

  /// Tập user id đang online trong phòng (Realtime Presence).
  Stream<Set<String>> watchOnline(String roomId);
}
