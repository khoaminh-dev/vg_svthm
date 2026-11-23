import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/voice/core/vy_reminders.dart';

DateTime at(int h, int m, [int d = 21]) => DateTime(2026, 11, d, h, m);

ReminderInputs inp({
  DateTime? now,
  bool fg = true,
  bool busy = false,
  bool quiet = false,
  String? dose,
  BpDue? bp,
  List<NewMessages> msgs = const [],
  bool eDose = true,
  bool eBp = true,
  bool eMsg = true,
}) => ReminderInputs(
  now: now ?? at(8, 0),
  foreground: fg,
  busy: busy,
  quiet: quiet,
  doseKey: dose,
  bpDue: bp,
  messages: msgs,
  enabledDose: eDose,
  enabledBp: eBp,
  enabledMessages: eMsg,
);

const bpDue = BpDue(slot: 'morning', key: 'bp:2026-11-21:morning');
NewMessages msg(String room, DateTime latest, {int n = 1}) => NewMessages(roomId: room, from: 'Giang', count: n, latest: latest);

void main() {
  group('ReminderMemory: nhớ qua lần mở lại app', () {
    test('đã nhắc rồi, mở lại app (nạp từ bản lưu) thì không nhắc lặp cùng một việc', () {
      final i = inp(dose: 'dose:a:0', bp: bpDue);
      final before = ReminderMemory();
      before.markShown(decideReminder(i, before)!, at(8, 0)); // nhắc thuốc
      final saved = before.snapshot(at(8, 1));

      final after = ReminderMemory()..restore(saved, at(8, 2)); // mở lại app
      expect(decideReminder(i, after)!.kind, ReminderKind.bp); // thuốc đã nhắc, chuyển sang việc kế
      after.markShown(decideReminder(i, after)!, at(8, 2));
      expect(decideReminder(i, after), isNull);
    });

    test('quá 36 giờ thì quên; "Để sau" gỡ khỏi bản lưu', () {
      final m = ReminderMemory();
      m.markShown(const ReminderPick(ReminderKind.dose, 'dose:old:0'), at(8, 0));
      expect(ReminderMemory().let((r) => r..restore(m.snapshot(at(8, 0)), at(8, 0).add(const Duration(hours: 40)))).done, isEmpty);

      final msg = const ReminderPick(ReminderKind.messages, 'msg:r:1');
      m.markShown(msg, at(8, 0));
      m.later(msg);
      expect(m.snapshot(at(8, 1)).containsKey('msg:r:1'), isFalse);
    });
  });

  group('decideReminder: ưu tiên và điều kiện chung', () {
    test('thuốc > đo huyết áp > tin nhắn khi cùng đến hạn', () {
      final i = inp(dose: 'dose:a:0', bp: bpDue, msgs: [msg('r1', at(7, 59))]);
      final mem = ReminderMemory();
      expect(decideReminder(i, mem)!.kind, ReminderKind.dose);
      mem.markShown(decideReminder(i, mem)!, at(8, 0));
      expect(decideReminder(i, mem)!.kind, ReminderKind.bp);
      mem.markShown(decideReminder(i, mem)!, at(8, 0));
      expect(decideReminder(i, mem)!.kind, ReminderKind.messages);
      mem.markShown(decideReminder(i, mem)!, at(8, 0));
      expect(decideReminder(i, mem), isNull);
    });

    test('app ở nền sau hoặc đang bận (Vy mở, SOS, đo, gọi): KHÔNG nhắc, kể cả thuốc', () {
      final mem = ReminderMemory();
      expect(decideReminder(inp(dose: 'dose:a:0', fg: false), mem), isNull);
      expect(decideReminder(inp(dose: 'dose:a:0', busy: true), mem), isNull);
      expect(decideReminder(inp(bp: bpDue, busy: true), mem), isNull);
    });

    test('không có gì cần nhắc thì null', () {
      expect(decideReminder(inp(), ReminderMemory()), isNull);
    });
  });

  group('thuốc', () {
    test('mỗi cữ chỉ nhắc MỘT lần; hoãn xong (mốc hoãn khác) là lần nhắc mới', () {
      final mem = ReminderMemory();
      final k1 = doseReminderKey('a', null);
      final p = decideReminder(inp(dose: k1), mem)!;
      mem.markShown(p, at(8, 0));
      expect(decideReminder(inp(dose: k1), mem), isNull);
      final k2 = doseReminderKey('a', at(8, 15)); // hoãn 15 phút
      expect(k2, isNot(k1));
      expect(decideReminder(inp(dose: k2), mem)!.kind, ReminderKind.dose);
    });

    test('giờ yên tĩnh KHÔNG chặn thuốc (D3), nhưng chặn đo huyết áp và tin nhắn', () {
      final mem = ReminderMemory();
      expect(decideReminder(inp(dose: 'dose:a:0', quiet: true), mem)!.kind, ReminderKind.dose);
      expect(decideReminder(inp(bp: bpDue, quiet: true), mem), isNull);
      expect(decideReminder(inp(msgs: [msg('r', at(7, 0))], quiet: true), mem), isNull);
    });

    test('tắt "nhắc thuốc" ở Cài đặt thì không nhắc thuốc nhưng các loại khác vẫn nhắc', () {
      final mem = ReminderMemory();
      final i = inp(dose: 'dose:a:0', bp: bpDue, eDose: false);
      expect(decideReminder(i, mem)!.kind, ReminderKind.bp);
    });

    test('doseIsDueForReminder: chưa tới giờ, quá cửa sổ, đang hoãn, đã uống thì không', () {
      final due = at(8, 0), end = at(10, 0);
      bool f(DateTime now, {bool pending = true, DateTime? snooze}) =>
          doseIsDueForReminder(now: now, dueAt: due, windowEnd: end, pending: pending, snoozedUntil: snooze);
      expect(f(at(7, 40)), isFalse); // cửa sổ "bấm Đã uống" mở sớm 30 phút nhưng KHÔNG nhắc sớm
      expect(f(at(8, 0)), isTrue);
      expect(f(at(9, 59)), isTrue);
      expect(f(at(10, 1)), isFalse);
      expect(f(at(8, 5), pending: false), isFalse);
      expect(f(at(8, 5), snooze: at(8, 15)), isFalse);
      expect(f(at(8, 16), snooze: at(8, 15)), isTrue);
    });
  });

  group('đo huyết áp', () {
    final slots = {'morning': '08:00', 'evening': '19:00'};

    test('tới giờ, chưa đo: nhắc; chưa tới giờ hoặc quá 3 giờ thì thôi', () {
      expect(bpReminderDue(at(7, 59), slots, const []), isNull);
      expect(bpReminderDue(at(8, 0), slots, const [])!.slot, 'morning');
      expect(bpReminderDue(at(10, 59), slots, const [])!.slot, 'morning');
      expect(bpReminderDue(at(11, 1), slots, const []), isNull);
      expect(bpReminderDue(at(19, 30), slots, const [])!.slot, 'evening');
    });

    test('đã đo quanh giờ đó (từ 1 giờ trước giờ nhắc) thì bỏ qua; đo hôm qua thì vẫn nhắc', () {
      expect(bpReminderDue(at(8, 30), slots, [at(7, 30)]), isNull);
      expect(bpReminderDue(at(8, 30), slots, [at(8, 10)]), isNull);
      expect(bpReminderDue(at(8, 30), slots, [at(7, 30, 20)]), isNotNull);
      expect(bpReminderDue(at(8, 30), slots, [at(6, 0)]), isNotNull); // sớm hơn 1 giờ trước giờ nhắc
    });

    test('mã theo ngày và buổi: nhắc buổi sáng rồi thì không nhắc lại, buổi tối là mã khác', () {
      final a = bpReminderDue(at(8, 30), slots, const [])!;
      final b = bpReminderDue(at(19, 30), slots, const [])!;
      expect(a.key, isNot(b.key));
      final mem = ReminderMemory();
      mem.markShown(ReminderPick(ReminderKind.bp, a.key), at(8, 30));
      expect(decideReminder(inp(bp: a), mem), isNull);
      expect(decideReminder(inp(bp: b), mem)!.kind, ReminderKind.bp);
    });

    test('slots hỏng thì bỏ qua, không văng', () {
      expect(bpReminderDue(at(8, 30), {'morning': 'abc', 'evening': ''}, const []), isNull);
    });
  });

  group('tin nhắn', () {
    test('groupNewMessages: chỉ tin sau mốc, bỏ phòng đang mở, gom theo phòng, mới nhất trước', () {
      final g = groupNewMessages([
        (roomId: 'a', from: 'Giang', at: at(8, 5)),
        (roomId: 'a', from: 'Giang', at: at(8, 7)),
        (roomId: 'b', from: 'Hoa', at: at(8, 6)),
        (roomId: 'c', from: 'Lan', at: at(7, 0)), // trước mốc
        (roomId: 'd', from: 'Minh', at: at(8, 9)), // phòng đang mở
      ], since: at(8, 0), openRoomId: 'd');
      expect(g.map((m) => m.roomId), ['a', 'b']);
      expect(g.first.count, 2);
      expect(g.first.latest, at(8, 7));
    });

    test('tối đa 1 lần nhắc tin nhắn mỗi 15 phút; tin đã nhắc không nhắc lại', () {
      final mem = ReminderMemory();
      final m1 = msg('a', at(8, 1));
      final p = decideReminder(inp(msgs: [m1]), mem)!;
      mem.markShown(p, at(8, 2));
      // tin mới ở phòng khác trong 15 phút: chờ
      expect(decideReminder(inp(now: at(8, 10), msgs: [msg('b', at(8, 8))]), mem), isNull);
      // đủ 15 phút: nhắc
      expect(decideReminder(inp(now: at(8, 17), msgs: [msg('b', at(8, 8))]), mem)!.kind, ReminderKind.messages);
      // tin cũ đã nhắc không nhắc lại dù đủ giờ
      expect(decideReminder(inp(now: at(8, 30), msgs: [m1]), mem), isNull);
    });

    test('"Để sau": nhắc lại đúng một lần', () {
      final mem = ReminderMemory();
      final m = msg('a', at(8, 1));
      final p = decideReminder(inp(msgs: [m]), mem)!;
      mem.markShown(p, at(8, 2));
      expect(mem.later(p), isTrue);
      expect(decideReminder(inp(now: at(8, 10), msgs: [m]), mem), isNull); // chưa đủ 15 phút
      final again = decideReminder(inp(now: at(8, 18), msgs: [m]), mem)!;
      mem.markShown(again, at(8, 18));
      expect(mem.later(again), isFalse); // không lặp vô hạn
      expect(decideReminder(inp(now: at(9, 0), msgs: [m]), mem), isNull);
    });
  });

  group('giờ yên tĩnh và câu nói', () {
    test('inQuietHours: qua nửa đêm, trong ngày, thiếu đầu, trùng giờ', () {
      expect(inQuietHours(at(23, 0), '22:00', '06:00'), isTrue);
      expect(inQuietHours(at(2, 0), '22:00', '06:00'), isTrue);
      expect(inQuietHours(at(6, 0), '22:00', '06:00'), isFalse);
      expect(inQuietHours(at(12, 0), '22:00', '06:00'), isFalse);
      expect(inQuietHours(at(13, 0), '12:00', '14:00'), isTrue);
      expect(inQuietHours(at(13, 0), null, '14:00'), isFalse);
      expect(inQuietHours(at(13, 0), '12:00', '12:00'), isFalse);
      expect(inQuietHours(at(13, 0), 'x', 'y'), isFalse);
    });

    test('reminderSpeech', () {
      expect(reminderSpeech(ReminderKind.dose, 'bác', doseWhat: 'túi Sáng'), 'Đến giờ uống thuốc rồi bác ơi. bác lấy túi Sáng nhé.');
      expect(reminderSpeech(ReminderKind.bp, 'cô'), 'Đến giờ đo huyết áp rồi cô ơi. cô ngồi yên 5 phút trước khi đo nhé.');
      expect(reminderSpeech(ReminderKind.messages, 'bác', from: 'Giang', count: 2), contains('2 tin mới từ Giang'));
      expect(reminderSpeech(ReminderKind.messages, 'bác', from: 'Giang'), contains('có tin mới từ Giang'));
    });
  });

  group('hỏi lại "đã uống chưa"', () {
    final due = at(8, 0);
    final end = at(10, 0);
    String? key(DateTime now, {bool pending = true, DateTime? snooze}) =>
        doseFollowUpKey(doseId: 'x', now: now, dueAt: due, windowEnd: end, pending: pending, snoozedUntil: snooze);

    test('chưa tới 15 phút: chưa hỏi; 15 phút: lần 1; 30 phút: lần 2', () {
      expect(key(at(8, 10)), isNull);
      expect(key(at(8, 15)), 'dosechk:x:0:1');
      expect(key(at(8, 29)), 'dosechk:x:0:1');
      expect(key(at(8, 30)), 'dosechk:x:0:2');
      expect(key(at(9, 30)), 'dosechk:x:0:2');
    });

    test('đã uống, quá cửa sổ hoặc đang hoãn thì không hỏi; hết hoãn thì tính lại từ lúc hết hoãn', () {
      expect(key(at(8, 20), pending: false), isNull);
      expect(key(at(10, 5)), isNull);
      expect(key(at(8, 20), snooze: at(8, 40)), isNull);
      expect(key(at(8, 45), snooze: at(8, 40)), isNull);
      expect(key(at(8, 56), snooze: at(8, 40)), startsWith('dosechk:x:'));
    });

    test('quyết định: hỏi lại sau khi đã nhắc; không dồn nếu vừa nhắc; một lần cho mỗi mốc', () {
      final mem = ReminderMemory();
      final first = decideReminder(
        ReminderInputs(now: at(8, 16), foreground: true, busy: false, doseCheckKey: 'dosechk:x:0:1'),
        mem,
      );
      expect(first?.kind, ReminderKind.doseCheck);
      mem.markShown(first!, at(8, 16));
      expect(
        decideReminder(ReminderInputs(now: at(8, 17), foreground: true, busy: false, doseCheckKey: 'dosechk:x:0:1'), mem),
        isNull,
      );
      // mốc 2 mà vừa mới nhắc 5 phút: chờ
      expect(
        decideReminder(ReminderInputs(now: at(8, 21), foreground: true, busy: false, doseCheckKey: 'dosechk:x:0:2'), mem),
        isNull,
      );
      expect(
        decideReminder(ReminderInputs(now: at(8, 31), foreground: true, busy: false, doseCheckKey: 'dosechk:x:0:2'), mem)?.kind,
        ReminderKind.doseCheck,
      );
    });

    test('nền sau, đang bận hoặc tắt nhắc thuốc thì không hỏi', () {
      final k = 'dosechk:x:0:1';
      expect(decideReminder(ReminderInputs(now: at(8, 16), foreground: false, busy: false, doseCheckKey: k), ReminderMemory()), isNull);
      expect(decideReminder(ReminderInputs(now: at(8, 16), foreground: true, busy: true, doseCheckKey: k), ReminderMemory()), isNull);
      expect(decideReminder(ReminderInputs(now: at(8, 16), foreground: true, busy: false, enabledDose: false, doseCheckKey: k), ReminderMemory()), isNull);
    });
  });
}


extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
