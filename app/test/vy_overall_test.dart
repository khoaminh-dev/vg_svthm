import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/domain/bp_voice.dart';
import 'package:vg_svthm/features/reminders/user_reminders.dart';
import 'package:vg_svthm/features/voice/core/vy_last.dart';
import 'package:vg_svthm/features/voice/core/vy_reminders.dart';
import 'package:vg_svthm/shared/widgets/elder_text_scale.dart';

// Kế hoạch Vy tổng thể (docs/KE_HOACH_VY_TONG_THE.md) đợt 3, 5, 7: nhắc việc, đọc lịch sử huyết áp, trí nhớ ngắn hạn, cỡ chữ.

DateTime d(int day, int h, int m) => DateTime(2026, 11, day, h, m);
BpReading r(int sys, int dia, DateTime at, {int? pulse}) => BpReading(systolic: sys, diastolic: dia, pulse: pulse, measuredAt: at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nhắc việc người dùng nhờ Vy', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('dueReminder: chỉ nhắc khi tới giờ, trong cửa sổ 4 giờ, chưa xong; việc cũ nhất trước', () {
      final a = UserReminder(id: 1, at: d(24, 8, 0), what: 'đi khám');
      final b = UserReminder(id: 2, at: d(24, 9, 0), what: 'gọi cho con');
      expect(dueReminder([a, b], d(24, 7, 59)), isNull, reason: 'chưa tới giờ');
      expect(dueReminder([a, b], d(24, 8, 0))?.id, 1);
      expect(dueReminder([a, b], d(24, 9, 30))?.id, 1, reason: 'việc cũ hơn nhắc trước');
      expect(dueReminder([a.copyWith(done: true), b], d(24, 9, 30))?.id, 2);
      expect(dueReminder([a], d(24, 12, 1)), isNull, reason: 'quá 4 giờ thì thôi');
    });

    test('lưu và đọc lại qua JSON, bỏ mục hỏng', () {
      final a = UserReminder(id: 7, at: d(24, 8, 0), what: 'uống thuốc', done: true);
      final back = UserReminder.fromJson(a.toJson())!;
      expect([back.id, back.at, back.what, back.done], [7, d(24, 8, 0), 'uống thuốc', true]);
      expect(UserReminder.fromJson('bậy'), isNull);
      expect(UserReminder.fromJson({'id': 1, 'at': 5, 'what': ''}), isNull);
      expect(UserReminder.fromJson({'id': 'x', 'at': 5, 'what': 'a'}), isNull);
    });

    test('thêm, xong, nhắc lại sau; đủ 20 việc chờ thì từ chối', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(userRemindersProvider.notifier);
      final now = d(24, 7, 0);
      final first = n.add(d(24, 8, 0), '  đi khám  ', now: now);
      expect(first, isNotNull);
      expect(first!.what, 'đi khám', reason: 'bỏ khoảng trắng thừa');
      expect(c.read(userRemindersProvider), hasLength(1));

      n.snooze(first.id, 10, now: d(24, 8, 1));
      expect(c.read(userRemindersProvider).first.at, d(24, 8, 11));

      n.markDone(first.id);
      expect(c.read(userRemindersProvider).first.done, isTrue);
      expect(n.pendingCount, 0);

      for (var i = 0; i < maxPendingReminders; i++) {
        expect(n.add(d(24, 9, 0).add(Duration(minutes: i)), 'việc $i', now: now), isNotNull, reason: 'việc thứ ${i + 1}');
      }
      expect(n.add(d(24, 20, 0), 'việc thừa', now: now), isNull, reason: 'đã đủ $maxPendingReminders việc chờ');
    });

    test('mã thông báo của nhắc việc nằm trong dải riêng, không đụng thuốc và huyết áp', () {
      expect(isUserReminderNotificationId(userReminderIdBase), isTrue);
      expect(isUserReminderNotificationId(userReminderIdBase + userReminderIdSpan - 1), isTrue);
      expect(isUserReminderNotificationId(userReminderIdBase + userReminderIdSpan), isFalse);
      expect(isUserReminderNotificationId(1000), isFalse);
      expect(isUserReminderNotificationId(2100000000), isFalse, reason: 'huyết áp bắt đầu từ 2,1 tỷ');
    });

    test('spokenWhen: nói giờ tự nhiên theo buổi và ngày', () {
      final now = d(24, 9, 5);
      expect(spokenWhen(d(24, 15, 30), now), '3 giờ rưỡi chiều nay');
      expect(spokenWhen(d(25, 8, 0), now), '8 giờ sáng mai');
      expect(spokenWhen(d(26, 19, 0), now), '7 giờ tối ngày kia');
      expect(spokenWhen(d(30, 12, 0), now), '12 giờ trưa ngày 30 tháng 11');
      expect(spokenWhen(d(24, 23, 5), now), '11 giờ 5 phút đêm nay');
    });
  });

  group('nhắc việc trong bộ nhắc chủ động', () {
    ReminderInputs inp({String? custom, String? dose, bool eBp = true, BpDue? bp}) => ReminderInputs(
      now: d(24, 8, 0),
      foreground: true,
      busy: false,
      quiet: false,
      doseKey: dose,
      bpDue: bp,
      customKey: custom,
      enabledDose: true,
      enabledBp: eBp,
      enabledMessages: true,
    );

    test('việc tự nhờ nhắc được nhắc dù đã tắt "Vy tự nhắc đo huyết áp"', () {
      final p = decideReminder(inp(custom: 'user:1:5', eBp: false), ReminderMemory());
      expect(p?.kind, ReminderKind.custom);
      expect(p?.key, 'user:1:5');
    });

    test('thuốc luôn nhắc trước việc tự đặt; việc tự đặt nhắc trước đo huyết áp', () {
      const bp = BpDue(slot: 'morning', key: 'bp:2026-11-24:morning');
      expect(decideReminder(inp(custom: 'user:1:5', dose: 'dose:1'), ReminderMemory())?.kind, ReminderKind.dose);
      expect(decideReminder(inp(custom: 'user:1:5', bp: bp), ReminderMemory())?.kind, ReminderKind.custom);
    });

    test('đã nhắc rồi thì không nhắc lại cùng một việc', () {
      final mem = ReminderMemory()..done.add('user:1:5');
      expect(decideReminder(inp(custom: 'user:1:5'), mem), isNull);
    });

    test('mã chống nhắc lặp đổi khi hẹn lại giờ', () {
      final a = UserReminder(id: 1, at: d(24, 8, 0), what: 'x');
      expect(userReminderKey(a), isNot(userReminderKey(a.copyWith(at: d(24, 8, 10)))));
    });
  });

  group('đọc lịch sử huyết áp bằng giọng', () {
    final now = d(24, 9, 0);
    final all = [
      r(150, 95, d(23, 7, 30), pulse: 80),
      r(138, 88, d(23, 20, 0)),
      r(122, 78, d(24, 7, 15)),
      r(165, 100, d(20, 8, 0)),
      r(110, 70, d(10, 8, 0)), // ngoài 7 ngày
    ];

    test('hôm qua: đếm lần đo và đọc từng lần, không khuyên gì', () {
      final s = bpHistorySay(all, 'yesterday', now, 'bác');
      expect(s, contains('Hôm qua bác đo 2 lần'));
      expect(s, contains('150 trên 95, mạch 80 lúc 7 giờ rưỡi sáng'));
      expect(s, contains('138 trên 88 lúc 8 giờ tối'));
      expect(s, isNot(contains('nên')));
    });

    test('hôm qua không đo: nói thật', () {
      expect(bpHistorySay([r(120, 80, d(10, 8, 0))], 'yesterday', now, 'bác'), 'Dạ, hôm qua bác không đo lần nào ạ.');
    });

    test('trung bình 7 ngày: không tính số đo cũ hơn và nói mức theo chuẩn', () {
      final s = bpHistorySay(all, 'week_avg', now, 'bác');
      // 150,138,122,165 → 143.75 ≈ 144; 95,88,78,100 → 90.25 ≈ 90
      expect(s, contains('144 trên 90, từ 4 lần đo'));
      expect(s, contains('Mức:'));
      expect(s, isNot(contains('Mới có')), reason: 'đủ 3 lần thì không cần nói chưa chắc');
    });

    test('ít hơn 3 lần đo thì nói chưa chắc', () {
      final s = bpHistorySay([r(130, 85, d(23, 8, 0)), r(128, 84, d(24, 8, 0))], 'week_avg', now, 'bác');
      expect(s, contains('Mới có 2 lần đo'));
    });

    test('cao nhất và thấp nhất trong 7 ngày', () {
      final hi = bpHistorySay(all, 'week_max', now, 'bác');
      expect(hi, contains('cao nhất'));
      expect(hi, contains('165 trên 100'));
      expect(hi, contains('ngày 20 tháng 11'));
      final lo = bpHistorySay(all, 'week_min', now, 'bác');
      expect(lo, contains('thấp nhất'));
      expect(lo, contains('122 trên 78'));
      expect(lo, contains('hôm nay'));
      expect(lo, isNot(contains('110 trên 70')));
    });

    test('mấy lần gần nhất: tối đa 3, mới nhất trước', () {
      final s = bpHistorySay(all, 'recent', now, 'bác');
      expect(s, startsWith('3 lần đo gần nhất của bác:'));
      expect(s.indexOf('122 trên 78'), lessThan(s.indexOf('138 trên 88')));
      expect(s, isNot(contains('165 trên 100')));
    });

    test('người thân hỏi về cha/mẹ: gọi đúng tên', () {
      expect(bpHistorySay(const [], 'recent', now, 'bác', who: 'bà Lan'), 'Dạ, bà Lan chưa đo lần nào ạ.');
      expect(bpHistorySay([r(120, 80, d(24, 8, 0))], 'recent', now, 'bác', who: 'bà Lan'), startsWith('1 lần đo gần nhất của bà Lan:'));
    });

    test('chế độ lạ không làm hỏng; danh sách chế độ đủ 5', () {
      expect(bpHistorySay(all, 'khac', now, 'bác'), 'Dạ, con chưa đọc được ạ.');
      expect(bpHistoryModes, {'yesterday', 'week_avg', 'week_max', 'week_min', 'recent'});
    });

    test('clockWords', () {
      expect(clockWords(d(24, 0, 10)), '12 giờ 10 phút đêm');
      expect(clockWords(d(24, 12, 0)), '12 giờ trưa');
      expect(clockWords(d(24, 18, 30)), '6 giờ rưỡi tối');
    });
  });

  group('trí nhớ ngắn hạn "trả lời ai"', () {
    test('nhớ người vừa nhắn, hết hạn sau 10 phút, bỏ tên rỗng', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(vyLastProvider.notifier);
      expect(n.snapshot(), isEmpty);
      n.setReplyTo('   ');
      expect(n.snapshot(), isEmpty);
      final t0 = d(24, 9, 0);
      n.setReplyTo(' Lan ', now: t0);
      expect(n.snapshot(now: t0.add(const Duration(minutes: 9))), {'replyTo': 'Lan'});
      expect(n.snapshot(now: t0.add(const Duration(minutes: 11))), isEmpty);
      n.clear();
      expect(n.snapshot(now: t0), isEmpty);
    });
  });

  group('cỡ chữ bằng giọng', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('tăng từng bước 0,15 và dừng ở mức tối đa; giảm dừng ở mức tối thiểu', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(elderTextBoostProvider.notifier);
      // cỡ chữ hệ thống 1,0 → nền người cao tuổi là 1,2; tối đa 2,0
      var ups = 0;
      while (n.bump(1, 1.0)) {
        ups++;
        expect(ups, lessThan(20), reason: 'phải dừng được');
      }
      expect(ups, 5, reason: '1,2 + 5 × 0,15 = 1,95; bước thứ 6 vượt 2,0');
      expect(c.read(elderTextBoostProvider), closeTo(0.75, 0.001));
      expect(n.bump(1, 1.0), isFalse);

      var downs = 0;
      while (n.bump(-1, 1.0)) {
        downs++;
        expect(downs, lessThan(20));
      }
      expect(c.read(elderTextBoostProvider) + elderScaleFor(1.0), greaterThanOrEqualTo(ElderTextBoostNotifier.minTotal - 0.001));
      expect(n.bump(-1, 1.0), isFalse);
    });

    test('cỡ chữ hệ thống lớn sẵn thì có ít bước tăng hơn', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(elderTextBoostProvider.notifier);
      var ups = 0;
      while (n.bump(1, 1.6)) {
        ups++;
        if (ups > 20) break;
      }
      expect(ups, 2, reason: '1,6 + 2 × 0,15 = 1,9; bước thứ 3 vượt 2,0');
    });
  });
}
