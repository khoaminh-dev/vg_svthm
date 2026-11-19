import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cờ "Vy Live đang chạy" dùng chung để Vy thường và Vy Live không tranh micro/loa,
/// và để lớp phủ hiện thanh "Kết thúc" ở mọi màn.
class LiveActive extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final liveActiveProvider = NotifierProvider<LiveActive, bool>(LiveActive.new);
