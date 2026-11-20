import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_screen.dart';
import 'package:vg_svthm/features/voice/core/control_locator.dart';
import 'package:vg_svthm/features/voice/core/control_registry.dart';
import 'package:vg_svthm/features/voice/core/vy_cursor.dart';

class FakeSurface implements VyCursorSurface {
  final events = <String>[];
  Offset? flewTo;
  String? label;
  bool instant = false;

  @override
  Future<void> flyTo(Offset to, {required Offset from, String? label, bool instant = false, double speed = 1}) async {
    flewTo = to;
    this.label = label;
    this.instant = instant;
    events.add('fly');
  }

  @override
  Future<void> click() async => events.add('click');

  @override
  Future<void> glowAround(Rect r, {Duration hold = Duration.zero}) async => events.add('glow');

  @override
  Future<void> hide({bool instant = false}) async => events.add('hide');
}

class FakeLocator implements ControlLocator {
  FakeLocator(this.rect);
  Rect? rect;
  VyControl? asked;

  @override
  Future<Rect?> locate(VyControl control) async {
    asked = control;
    return rect;
  }
}

SemNode n(int id, String label, {Rect? rect, bool tap = true, bool button = true}) =>
    SemNode(id: id, label: label, rect: rect ?? Rect.fromLTWH(10.0 * id, 100, 120, 60), canTap: tap, button: button);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bestMatch: nhãn điều khiển ↔ nút trên màn hình', () {
    const taken = VyControl(id: 'meds.taken.x', label: 'Đã uống Túi Tối', aliases: ['uống rồi']);

    test('nhãn trợ năng là một phần nguyên vẹn của nhãn điều khiển', () {
      final hit = bestMatch(taken, [n(1, 'Thuốc'), n(2, 'Đã uống'), n(3, 'Bỏ qua cữ này')]);
      expect(hit?.id, 2);
    });

    test('khớp đúng nhãn thắng khớp một phần; nút chạm được thắng chữ trơ', () {
      const c = VyControl(id: 'a', label: 'Thuốc');
      expect(bestMatch(c, [n(1, 'Thuốc kế tiếp', tap: false, button: false), n(2, 'Thuốc')])?.id, 2);
      expect(bestMatch(c, [n(1, 'Thuốc', tap: false, button: false), n(2, 'Thuốc')])?.id, 2);
    });

    test('không có nút nào khớp thì null; nút quá nhỏ bị bỏ qua', () {
      expect(bestMatch(taken, [n(1, 'Tin nhắn'), n(2, 'Cộng đồng')]), isNull);
      expect(bestMatch(taken, [n(1, 'Đã uống', rect: const Rect.fromLTWH(0, 0, 2, 2))]), isNull);
    });

    test('so không dấu và không phân biệt hoa thường', () {
      const c = VyControl(id: 'a', label: 'Về trang chủ');
      expect(bestMatch(c, [n(1, 've trang chu')])?.id, 1);
    });

    test('từ đồng nghĩa cũng khớp', () {
      expect(bestMatch(taken, [n(1, 'Uống rồi')])?.id, 1);
    });
  });

  group('VyCursorController', () {
    late ControlRegistry reg;
    late FakeSurface surface;
    late FakeLocator locator;
    late int started;
    late bool reduce;
    late bool enabled;
    late List<String> hits;

    VyCursorController make() => VyCursorController(
      registry: reg,
      locator: locator,
      surface: () => surface,
      onStart: () => started++,
      orb: () => const Offset(48, 800),
      reduceMotion: () => reduce,
      enabled: () => enabled,
      timeScale: 0,
    );

    setUp(() {
      reg = ControlRegistry();
      surface = FakeSurface();
      locator = FakeLocator(const Rect.fromLTWH(100, 200, 200, 80));
      started = 0;
      reduce = false;
      enabled = true;
      hits = [];
      reg.set(Object(), controls: [
        VyControl(id: 'meds.taken', label: 'Đã uống', onInvoke: () => hits.add('taken')),
        VyControl(id: 'prof.captions', label: 'Hiện chữ', kind: VyKind.toggle, value: true, onSet: (v) => hits.add('set:$v')),
        const VyControl(id: 'prof.logout', label: 'Đăng xuất', level: VyLevel.selfOnly),
        VyControl(id: 'undo', label: 'Hoàn tác', enabled: false, onInvoke: () => hits.add('undo')),
      ]);
    });

    test('bấm: thu panel, bay tới tâm nút, bấm đúng một lần, rồi ẩn', () async {
      final c = make();
      await c.press('meds.taken');
      expect(started, 1);
      expect(surface.flewTo, const Offset(200, 240));
      expect(surface.label, 'Bấm Đã uống');
      expect(surface.events, ['fly', 'click', 'hide']);
      expect(hits, ['taken']);
      expect(c.active, isFalse);
    });

    test('công tắc: nhãn "Tắt" và đặt đúng giá trị', () async {
      final c = make();
      await c.press('prof.captions', set: false);
      expect(surface.label, 'Tắt');
      expect(hits, ['set:false']);
    });

    test('không thấy nút trên màn hình: không bay, làm thẳng', () async {
      locator.rect = null;
      final c = make();
      await c.press('meds.taken');
      expect(surface.events, isEmpty);
      expect(hits, ['taken']);
    });

    test('tắt con trỏ hoặc không có bề mặt: làm thẳng, không gọi bộ định vị', () async {
      enabled = false;
      final c = make();
      await c.press('meds.taken');
      expect(locator.asked, isNull);
      expect(surface.events, isEmpty);
      expect(hits, ['taken']);
    });

    test('giảm chuyển động của hệ điều hành: nhảy thẳng (instant)', () async {
      reduce = true;
      final c = make();
      await c.press('meds.taken');
      expect(surface.instant, isTrue);
      expect(hits, ['taken']);
    });

    test('mức 3: point chỉ bay + khung sáng, KHÔNG BẤM; press cũng không bấm được', () async {
      final c = make();
      await c.point('prof.logout');
      expect(surface.events, ['fly', 'glow', 'hide']);
      expect(surface.label, 'Bác tự bấm');
      expect(hits, isEmpty);
      surface.events.clear();
      await c.press('prof.logout');
      expect(hits, isEmpty); // registry từ chối mức 3 dù con trỏ có bay
    });

    test('check không bấm; trả đúng kết quả', () {
      final c = make();
      expect(c.check('meds.taken'), VyInvokeResult.done);
      expect(c.check('prof.logout'), VyInvokeResult.selfOnly);
      expect(c.check('undo'), VyInvokeResult.disabled);
      expect(c.check('khong.co'), VyInvokeResult.notFound);
      expect(hits, isEmpty);
    });

    test('người dùng chạm (cancel) giữa chừng: dừng, KHÔNG bấm, ẩn con trỏ', () async {
      locator = FakeLocator(const Rect.fromLTWH(100, 200, 200, 80));
      final c = VyCursorController(
        registry: reg,
        locator: locator,
        surface: () => surface,
        onStart: () => started++,
        orb: () => Offset.zero,
        timeScale: 1,
      );
      final f = c.press('meds.taken');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.active, isTrue);
      c.cancel(); // người dùng chạm vào màn hình
      await f;
      expect(hits, isEmpty);
      expect(surface.events.contains('click'), isFalse);
      expect(surface.events.last, 'hide');
      expect(c.active, isFalse);
    });

    test('hai việc liên tiếp: việc sau huỷ việc trước, chỉ việc sau bấm', () async {
      final c = VyCursorController(
        registry: reg,
        locator: locator,
        surface: () => surface,
        onStart: () {},
        orb: () => Offset.zero,
        timeScale: 1,
      );
      final first = c.press('meds.taken');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final second = c.press('prof.captions', set: false);
      await Future.wait([first, second]);
      expect(hits, ['set:false']);
    });
  });

  testWidgets('đánh số trên video thật: số 1–10 hiện khi Vy bật, không hiện khi tắt', (t) async {
    VideoItem v(int i) => VideoItem(id: 'v$i', title: 'Bài $i', author: 'K', thumbnailUrl: '');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Column(children: [
            VideoCard(item: v(1), number: 1, onTap: () {}),
            VideoCard(item: v(2), onTap: () {}),
          ])),
        ),
      ),
    );
    expect(find.byKey(const Key('video-number-1')), findsOneWidget);
    expect(find.byKey(const Key('video-number-2')), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
