/// Định dạng ngày giờ kiểu người Việt, dùng cho danh sách chat và tin nhắn.
abstract final class TimeFormat {
  static String _two(int n) => n.toString().padLeft(2, '0');

  static const _weekdays = [
    'Thứ hai',
    'Thứ ba',
    'Thứ tư',
    'Thứ năm',
    'Thứ sáu',
    'Thứ bảy',
    'Chủ nhật',
  ];

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Số ngày lịch giữa [t] và [now] (0 = cùng ngày, 1 = hôm qua).
  static int daysAgo(DateTime t, DateTime now) =>
      _day(now).difference(_day(t)).inDays;

  static bool sameDay(DateTime a, DateTime b) => daysAgo(a, b) == 0;

  static String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// Giờ rút gọn ở cột phải của danh sách: hôm nay "09:05", hôm qua "Hôm qua", trong tuần "Thứ ba", xa hơn "12/11".
  static String listTime(DateTime t, DateTime now) {
    final d = daysAgo(t, now);
    if (d <= 0) return hm(t);
    if (d == 1) return 'Hôm qua';
    if (d < 7) return _weekdays[t.weekday - 1];
    return t.year == now.year
        ? '${_two(t.day)}/${_two(t.month)}'
        : '${_two(t.day)}/${_two(t.month)}/${t.year}';
  }

  /// Nhãn ngăn cách ngày trong khung chat.
  static String dayLabel(DateTime t, DateTime now) {
    final d = daysAgo(t, now);
    if (d <= 0) return 'Hôm nay';
    if (d == 1) return 'Hôm qua';
    final date = t.year == now.year
        ? '${_two(t.day)}/${_two(t.month)}'
        : '${_two(t.day)}/${_two(t.month)}/${t.year}';
    return d < 7 ? '${_weekdays[t.weekday - 1]}, $date' : date;
  }
}
