import 'bp_models.dart';

/// Đọc lịch sử huyết áp bằng giọng (kế hoạch docs/KE_HOACH_VY_TONG_THE.md F5): "số đo hôm qua", "trung bình một tuần",
/// "cao nhất tuần này", "mấy lần đo gần đây". Chỉ đọc số và mức theo chuẩn, KHÔNG khuyên gì (nguyên tắc AHA đã chốt).
const bpHistoryModes = {'yesterday', 'week_avg', 'week_max', 'week_min', 'recent'};

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _part(int h) => h < 5 ? 'đêm' : h < 11 ? 'sáng' : h < 13 ? 'trưa' : h < 18 ? 'chiều' : h < 22 ? 'tối' : 'đêm';

/// "7 giờ sáng", "7 giờ 30 sáng", "3 giờ 5 phút chiều".
String clockWords(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute == 0 ? '' : t.minute == 30 ? ' rưỡi' : ' ${t.minute} phút';
  return '$h12 giờ$m ${_part(t.hour)}';
}

String _day(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  return switch (today.difference(d).inDays) {
    0 => 'hôm nay',
    1 => 'hôm qua',
    _ => 'ngày ${t.day} tháng ${t.month}',
  };
}

String _one(BpReading r, DateTime now, {bool withDay = false}) {
  final pulse = r.pulse == null ? '' : ', mạch ${r.pulse}';
  return '${r.systolic} trên ${r.diastolic}$pulse lúc ${clockWords(r.measuredAt)}${withDay ? ' ${_day(r.measuredAt, now)}' : ''}';
}

/// [who] là tên người được hỏi khi người thân hỏi về cha/mẹ ("Lan"); null thì nói về chính người nghe.
String bpHistorySay(List<BpReading> all, String mode, DateTime now, String hon, {String? who}) {
  final h = hon.isEmpty ? 'bác' : hon;
  final sorted = [...all]..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  final today = DateTime(now.year, now.month, now.day);
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  switch (mode) {
    case 'yesterday':
      final y = today.subtract(const Duration(days: 1));
      final list = sorted.where((r) => sameDay(r.measuredAt, y)).toList();
      if (list.isEmpty) return 'Dạ, hôm qua $h không đo lần nào ạ.';
      final shown = list.take(3).map((r) => _one(r, now)).join('; ');
      final more = list.length > 3 ? ' Còn ${list.length - 3} lần nữa.' : '';
      return 'Hôm qua $h đo ${list.length} lần: $shown.$more';
    case 'week_avg':
      final since = today.subtract(const Duration(days: 6));
      final list = sorted.where((r) => !r.measuredAt.isBefore(since)).toList();
      if (list.isEmpty) return 'Dạ, 7 ngày qua $h chưa đo lần nào nên con chưa tính trung bình được ạ.';
      final s = (list.fold<int>(0, (a, r) => a + r.systolic) / list.length).round();
      final d = (list.fold<int>(0, (a, r) => a + r.diastolic) / list.length).round();
      final cat = BpCategory.of(s, d);
      final few = list.length < 3 ? ' Mới có ${list.length} lần đo nên con chưa chắc phản ánh đúng.' : '';
      return 'Trung bình 7 ngày qua của $h là $s trên $d, từ ${list.length} lần đo. Mức: ${cat.label}.$few';
    case 'week_max':
    case 'week_min':
      final since = today.subtract(const Duration(days: 6));
      final list = sorted.where((r) => !r.measuredAt.isBefore(since)).toList();
      if (list.isEmpty) return 'Dạ, 7 ngày qua $h chưa đo lần nào ạ.';
      final high = mode == 'week_max';
      final r = list.reduce((a, b) {
        final c = a.systolic != b.systolic ? a.systolic.compareTo(b.systolic) : a.diastolic.compareTo(b.diastolic);
        return (high ? c >= 0 : c <= 0) ? a : b;
      });
      return 'Lần đo ${high ? 'cao' : 'thấp'} nhất trong 7 ngày qua của $h: ${_one(r, now, withDay: true)}. Mức: ${BpCategory.of(r.systolic, r.diastolic).label}.';
    case 'recent':
      if (sorted.isEmpty) return 'Dạ, ${who ?? _cap(h)} chưa đo lần nào ạ.';
      final last = sorted.reversed.take(3).toList();
      return '${last.length} lần đo gần nhất của ${who ?? h}: ${last.map((r) => _one(r, now, withDay: true)).join('; ')}.';
  }
  return 'Dạ, con chưa đọc được ạ.';
}
