import '../../../shared/models/profile.dart';
import 'message.dart';
import 'room.dart';

abstract interface class ChatRepository {
  Future<List<Room>> fetchRooms();

  /// Tạo phòng và tự thêm người tạo vào làm thành viên.
  Future<Room> createRoom(String name);

  /// Mời người dùng vào phòng theo username.
  Future<void> addMember(String roomId, String username);

  Future<List<Profile>> fetchMembers(String roomId);

  /// Danh sách tin nhắn của phòng (cũ đến mới), cập nhật realtime.
  Stream<List<Message>> watchMessages(String roomId);

  Future<void> sendMessage(String roomId, String content);

  /// Tập user id đang online trong phòng (Realtime Presence).
  Stream<Set<String>> watchOnline(String roomId);
}
