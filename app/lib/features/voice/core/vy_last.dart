import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trí nhớ hội thoại ngắn hạn (kế hoạch docs/KE_HOACH_VY_TONG_THE.md đợt 7): Vy vừa đọc tin của ai thì
/// "trả lời là dạ" hiểu là trả lời đúng người đó. Hết hạn sau [lastTtl]; chỉ nhớ tên, không nhớ nội dung tin.
class VyLast {
  const VyLast({required this.replyTo, required this.at});

  /// Tên người vừa nhắn (đúng như danh bạ).
  final String replyTo;
  final DateTime at;
}

const lastTtl = Duration(minutes: 10);

class VyLastNotifier extends Notifier<VyLast?> {
  @override
  VyLast? build() => null;

  void setReplyTo(String name, {DateTime? now}) {
    final n = name.trim();
    if (n.isEmpty) return;
    state = VyLast(replyTo: n, at: now ?? DateTime.now());
  }

  void clear() => state = null;

  /// Gửi lên máy chủ mỗi lượt; rỗng nếu đã hết hạn.
  Map<String, Object?> snapshot({DateTime? now}) {
    final s = state;
    if (s == null) return const {};
    if ((now ?? DateTime.now()).difference(s.at) > lastTtl) return const {};
    return {'replyTo': s.replyTo};
  }
}

final vyLastProvider = NotifierProvider<VyLastNotifier, VyLast?>(VyLastNotifier.new);
