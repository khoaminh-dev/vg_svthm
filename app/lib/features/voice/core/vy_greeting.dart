/// Lời chào ngắn của Vy mỗi lần mở (quyết định D20): đọc ngay lúc chạm bằng giọng máy, không chờ kết nối.
///
/// - Mở lại trong vòng [recentWindow] sau lần đóng trước: chỉ "Dạ?" cho gọn.
/// - Còn lại xoay vòng vài câu (tối đa 5 từ) để không nhàm.
const recentWindow = Duration(minutes: 5);

/// Buổi trong ngày theo giờ: sáng (trước 11), trưa (11 đến 13), chiều (14 đến 17), tối (từ 18).
String partOfDay(int hour) {
  if (hour < 11) return 'sáng';
  if (hour < 14) return 'trưa';
  if (hour < 18) return 'chiều';
  return 'tối';
}

/// [variant] chọn câu (xoay vòng); [recent] là mở lại ngay sau lần đóng trước.
String vyGreeting({
  required DateTime now,
  required String honorific,
  required bool recent,
  int variant = 0,
}) {
  if (recent) return 'Dạ?';
  final h = honorific.trim().isEmpty ? 'bác' : honorific.trim();
  switch (variant % 3) {
    case 0:
      return 'Dạ, con nghe $h ạ';
    case 1:
      return 'Chào $h buổi ${partOfDay(now.hour)} ạ';
    default:
      return 'Dạ, $h cần gì ạ';
  }
}

/// Câu hỏi khi người dùng im lặng 30 giây.
String vyStillThere(String honorific) {
  final h = honorific.trim().isEmpty ? 'bác' : honorific.trim();
  return '${h[0].toUpperCase()}${h.substring(1)} còn cần con không ạ?';
}
