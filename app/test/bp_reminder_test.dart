import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/bp/data/bp_reminder_plan.dart';

void main() {
  final now = DateTime(2026, 11, 17, 7, 0);
  const slots = {'morning': '08:00', 'evening': '19:00'};

  List<PlannedReminder> plan({
    DateTime? at,
    Map<String, String> s = slots,
    bool measured = false,
    String? qs,
    String? qe,
  }) => planBpReminders(
    now: at ?? now,
    slots: s,
    measuredToday: measured,
    quietStart: qs,
    quietEnd: qe,
  );

  test('lịch: sáng + tối, mỗi giờ có đúng một lần nhắc lại sau 30 phút', () {
    final p = plan().where((r) => r.at.day == 17).toList();
    expect(p.map((r) => r.at.hour * 100 + r.at.minute), [800, 830, 1900, 1930]);
    expect(p.where((r) => r.followUp).length, 2);
  });

  test('hôm nay đã đo thì bỏ hết nhắc hôm nay nhưng vẫn giữ các ngày sau', () {
    final p = plan(measured: true);
    expect(p.where((r) => r.at.day == 17), isEmpty);
    expect(p.where((r) => r.at.day == 18), isNotEmpty);
  });

  test('chỉ giữ các lần ở tương lai; nhắc lại còn nếu lần đầu đã qua', () {
    final p = plan(at: DateTime(2026, 11, 17, 8, 10)).where((r) => r.at.day == 17).toList();
    expect(p.first.followUp, isTrue);
    expect(p.first.at, DateTime(2026, 11, 17, 8, 30));
  });

  test('không dồn dập: chỉ một nhắc lại cho mỗi giờ', () {
    final p = plan(s: const {'morning': '08:00'});
    expect(p.length, bpReminderDays * 2);
  });

  test('giờ yên tĩnh qua nửa đêm bỏ nhắc rơi vào đó', () {
    final p = plan(s: const {'morning': '08:00', 'evening': '22:30'}, qs: '22:00', qe: '06:00');
    expect(p.where((r) => r.slot == 'evening'), isEmpty);
    expect(p.where((r) => r.slot == 'morning'), isNotEmpty);
  });

  test('nhắc lại rơi vào giờ yên tĩnh thì bỏ, nhắc chính vẫn giữ', () {
    final p = plan(s: const {'morning': '08:00'}, qs: '08:15', qe: '09:00').where((r) => r.at.day == 17);
    expect(p.map((r) => r.followUp), [false]);
  });

  test('inQuietHours', () {
    expect(inQuietHours(DateTime(2026, 1, 1, 23), '22:00', '06:00'), isTrue);
    expect(inQuietHours(DateTime(2026, 1, 1, 5, 59), '22:00', '06:00'), isTrue);
    expect(inQuietHours(DateTime(2026, 1, 1, 6), '22:00', '06:00'), isFalse);
    expect(inQuietHours(DateTime(2026, 1, 1, 13), '12:00', '14:00'), isTrue);
    expect(inQuietHours(DateTime(2026, 1, 1, 13), null, null), isFalse);
  });

  test('giờ sai định dạng bị bỏ qua', () {
    expect(plan(s: const {'morning': 'abc'}), isEmpty);
  });

  test('remindersShown: chỉ tính lần đã đến giờ trong khoảng (since, now]', () {
    final stored = plan();
    final shown = remindersShown(stored, now, DateTime(2026, 11, 17, 8, 40));
    expect(shown.map((r) => r.followUp), [false, true]);
    expect(remindersShown(stored, DateTime(2026, 11, 17, 8, 40), DateTime(2026, 11, 17, 9)), isEmpty);
  });

  test('json khứ hồi', () {
    final r = plan().first;
    expect(PlannedReminder.fromJson(r.toJson()), r);
  });
}
