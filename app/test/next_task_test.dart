import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/home/domain/next_task.dart';

import 'meds_test.dart' show dose;

void main() {
  final now = DateTime(2026, 11, 23, 9, 0);

  test('không có gì: không còn việc', () {
    expect(pickNextTask(now: now).kind, NextTaskKind.none);
  });

  test('thuốc đến giờ thắng đến giờ đo huyết áp', () {
    final d = dose('d1', 'Sáng', now.subtract(const Duration(minutes: 5)));
    final t = pickNextTask(now: now, dose: d, bpSlots: {'morning': '08:00'});
    expect(t.kind, NextTaskKind.doseDue);
  });

  test('đến giờ đo mà chưa đo: việc là đo huyết áp', () {
    final t = pickNextTask(now: now, bpSlots: {'morning': '08:00'});
    expect(t.kind, NextTaskKind.bpDue);
  });

  test('đã đo quanh giờ nhắc thì không nhắc đo nữa', () {
    final t = pickNextTask(
      now: now,
      bpSlots: {'morning': '08:00'},
      measured: [DateTime(2026, 11, 23, 8, 10)],
    );
    expect(t.kind, NextTaskKind.none);
  });

  test('chưa bật nhắc đo (không có giờ): bỏ qua việc đo, còn thuốc kế tiếp', () {
    final d = dose('d2', 'Tối', now.add(const Duration(hours: 5)));
    final t = pickNextTask(now: now, dose: d);
    expect(t.kind, NextTaskKind.doseNext);
    expect(t.dose, d);
  });

  test('quá cửa sổ 3 giờ sau giờ nhắc thì thôi', () {
    final t = pickNextTask(now: DateTime(2026, 11, 23, 12, 0), bpSlots: {'morning': '08:00'});
    expect(t.kind, NextTaskKind.none);
  });
}
