import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/camera/data/camera_backend.dart';
import 'package:vg_svthm/features/camera/domain/camera_events.dart';
import 'package:vg_svthm/features/camera/domain/detection_data.dart';
import 'package:vg_svthm/features/camera/presentation/camera_entry_card.dart';
import 'package:vg_svthm/features/camera/presentation/camera_providers.dart';
import 'package:vg_svthm/features/camera/presentation/camera_screen.dart';
import 'package:vg_svthm/features/camera/presentation/detection_painter.dart';

Map<String, dynamic> _obj(int id, String label, double x, double y, double w, double h) =>
    {'id': id, 'label': label, 'x': x, 'y': y, 'w': w, 'h': h};

String _doc(List<Map<String, dynamic>> frames, {double duration = 20}) =>
    jsonEncode({'video': 'x.mp4', 'duration': duration, 'frames': frames});

const _bed = [0.2, 0.4, 0.6, 0.4];

/// Một người nằm trong khung giường suốt [0, to] giây, mỗi 0.5 giây một khung.
DetectionData _lying({double to = 12}) {
  final frames = <Map<String, dynamic>>[];
  for (var i = 0; i <= to * 2; i++) {
    frames.add({
      't': i / 2,
      'objs': [
        _obj(1, 'bed', _bed[0], _bed[1], _bed[2], _bed[3]),
        _obj(7, 'person', 0.3, 0.5, 0.3, 0.12),
      ],
    });
  }
  return DetectionData.parse(_doc(frames, duration: to));
}

/// Người đứng (cao 0.5) rồi xẹp xuống còn 0.15 trong 1 giây ở t=[at], không có giường nào gần đó.
DetectionData _fall({double at = 2}) {
  final frames = <Map<String, dynamic>>[];
  for (var i = 0; i <= 20; i++) {
    final t = i / 2;
    final collapsed = t >= at + 1;
    final mid = t > at && t < at + 1;
    final y = collapsed ? 0.62 : (mid ? 0.4 : 0.2);
    final h = collapsed ? 0.15 : (mid ? 0.3 : 0.5);
    final w = collapsed ? 0.3 : 0.12;
    frames.add({
      't': t,
      'objs': [
        _obj(9, 'person', 0.4, y, w, h),
      ],
    });
  }
  return DetectionData.parse(_doc(frames, duration: 10));
}

class _FakePlayer implements CameraPlayer {
  _FakePlayer({this.failStart = false});

  final bool failStart;
  double pos = 0;
  bool disposed = false;

  @override
  Future<void> start() async {
    if (failStart) throw Exception('no video');
  }

  @override
  double get seconds => pos;

  @override
  double get aspect => 16 / 9;

  @override
  Future<void> seek(double seconds) async => pos = seconds;

  @override
  Future<void> restart() async => pos = 0;

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);

  @override
  void dispose() => disposed = true;
}

class _FakeBackend implements CameraBackend {
  _FakeBackend({this.data, this.failFirst = false});

  final DetectionData? data;
  bool failFirst;
  final players = <_FakePlayer>[];

  @override
  CameraPlayer createPlayer(CameraFeed feed) {
    final p = _FakePlayer(failStart: failFirst);
    failFirst = false;
    players.add(p);
    return p;
  }

  @override
  Future<DetectionData?> loadDetections(CameraFeed feed) async => data;
}

const _feeds = [
  CameraFeed(id: 'a', title: 'Phòng 1', videoUrl: 'u/a.mp4', detectionsUrl: 'u/a.json'),
  CameraFeed(id: 'b', title: 'Phòng 2', videoUrl: 'u/b.mp4', detectionsUrl: 'u/b.json'),
];

void main() {
  group('DetectionData', () {
    test('nội suy vị trí giữa hai khung theo id', () {
      final d = DetectionData.parse(
        _doc([
          {'t': 0.0, 'objs': [_obj(1, 'person', 0.0, 0.0, 0.2, 0.4)]},
          {'t': 1.0, 'objs': [_obj(1, 'person', 0.4, 0.2, 0.2, 0.4)]},
        ]),
      );
      final o = d.objectsAt(0.5).single;
      expect(o.rect.left, closeTo(0.2, 1e-9));
      expect(o.rect.top, closeTo(0.1, 1e-9));
    });

    test('vật chỉ có ở một khung chỉ giữ trong thời gian ngắn', () {
      final d = DetectionData.parse(
        _doc([
          {'t': 0.0, 'objs': [_obj(1, 'person', 0.1, 0.1, 0.1, 0.1)]},
          {'t': 2.0, 'objs': <Map<String, dynamic>>[]},
        ]),
      );
      expect(d.objectsAt(0.2), hasLength(1));
      expect(d.objectsAt(1.0), isEmpty);
    });

    test('ngoài khoảng dữ liệu thì rỗng, không lỗi', () {
      final d = _lying(to: 2);
      expect(d.objectsAt(-5), isEmpty);
      expect(d.objectsAt(99), isEmpty);
      expect(DetectionData.parse(_doc([])).objectsAt(1), isEmpty);
    });
  });

  group('classifyPerson', () {
    const bed = DetObject(id: 1, label: 'bed', rect: Rect.fromLTWH(0.2, 0.4, 0.6, 0.4));

    DetObject p(double x, double y, double w, double h) =>
        DetObject(id: 2, label: 'person', rect: Rect.fromLTWH(x, y, w, h));

    test('nằm ngang trong giường là nằm', () {
      expect(classifyPerson(p(0.3, 0.5, 0.3, 0.12), [bed]), PersonState.lying);
    });

    test('ngồi trên giường là ngồi', () {
      expect(classifyPerson(p(0.4, 0.4, 0.12, 0.3), [bed]), PersonState.sitting);
    });

    test('đứng cao hẹp là đi lại dù chồng lên giường', () {
      expect(classifyPerson(p(0.4, 0.2, 0.06, 0.5), [bed]), PersonState.standing);
    });

    test('ngoài giường là đi lại; không có giường cũng vậy', () {
      expect(classifyPerson(p(0.9, 0.1, 0.05, 0.3), [bed]), PersonState.standing);
      expect(classifyPerson(p(0.3, 0.5, 0.3, 0.12), const []), PersonState.standing);
    });
  });

  group('CameraAnalysis', () {
    test('nằm xuống sinh sự kiện thông tin và không báo ầm ĩ', () {
      final a = CameraAnalysis.build(_lying(to: 5));
      expect(a.events.where((e) => e.level == AlertLevel.info), hasLength(1));
      expect(a.events.where((e) => e.level != AlertLevel.info), isEmpty);
    });

    test('nằm quá ngưỡng demo thì vàng, ngưỡng thật thì chưa', () {
      final d = _lying(to: 20);
      final demo = CameraAnalysis.build(d);
      final watch = demo.events.where((e) => e.level == AlertLevel.watch);
      expect(watch, hasLength(1));
      expect(watch.single.t, closeTo(8, 0.6));
      final real = CameraAnalysis.build(d, thresholds: AlertThresholds.real);
      expect(real.events.where((e) => e.level == AlertLevel.watch), isEmpty);
    });

    test('không thấy ai quá ngưỡng thì đỏ', () {
      final frames = <Map<String, dynamic>>[
        for (var i = 0; i <= 30; i++)
          {
            't': i / 2,
            'objs': i < 4
                ? [_obj(3, 'person', 0.3, 0.2, 0.06, 0.4)]
                : <Map<String, dynamic>>[],
          },
      ];
      final a = CameraAnalysis.build(DetectionData.parse(_doc(frames, duration: 15)));
      final urgent = a.events.where((e) => e.level == AlertLevel.urgent);
      expect(urgent, hasLength(1));
      expect(urgent.single.text, contains('Không thấy ai'));
    });

    test('trạng thái chớp ngắn dưới 3 giây không thành sự kiện', () {
      final frames = <Map<String, dynamic>>[];
      for (var i = 0; i <= 10; i++) {
        final lying = i >= 4 && i <= 6; // 1 giây
        frames.add({
          't': i / 2,
          'objs': [
            _obj(1, 'bed', _bed[0], _bed[1], _bed[2], _bed[3]),
            lying
                ? _obj(7, 'person', 0.3, 0.5, 0.3, 0.12)
                : _obj(7, 'person', 0.9, 0.1, 0.05, 0.3),
          ],
        });
      }
      final a = CameraAnalysis.build(DetectionData.parse(_doc(frames, duration: 5)));
      expect(a.events, isEmpty);
    });

    test('tóm tắt đếm theo tư thế', () {
      final d = _lying(to: 10);
      final a = CameraAnalysis.build(d);
      final s = StateSummary.at(d, a, 6);
      expect(s.lying, 1);
      expect(s.text, '1 người nằm');
      expect(const StateSummary().text, 'Chưa thấy ai');
    });

    test('gần giống té ngã: khung xẹp nhanh ngoài giường là mức vàng, không bao giờ đỏ', () {
      final a = CameraAnalysis.build(_fall());
      final falls = a.events.where((e) => e.fall).toList();
      expect(falls, isNotEmpty);
      expect(falls.first.level, AlertLevel.watch);
      expect(falls.first.text, contains('gần giống té ngã'));
      expect(falls.first.personId, 9);
      expect(a.events.where((e) => e.level == AlertLevel.urgent && e.fall), isEmpty);
    });

    test('nằm xuống giường từ từ không bị coi là té ngã', () {
      final a = CameraAnalysis.build(_lying());
      expect(a.events.where((e) => e.fall), isEmpty);
    });

    test('té ngã chỉ báo một lần trong 8 giây (không lặp mỗi khung)', () {
      final a = CameraAnalysis.build(_fall());
      expect(a.events.where((e) => e.fall).length, 1);
    });

    test('activeAlert chỉ trả vàng/đỏ trong cửa sổ gần nhất', () {
      const events = [
        CameraEvent(t: 2, level: AlertLevel.info, text: 'a'),
        CameraEvent(t: 5, level: AlertLevel.watch, text: 'b'),
      ];
      expect(activeAlert(events, 3), isNull);
      expect(activeAlert(events, 6)?.text, 'b');
      expect(activeAlert(events, 20), isNull);
    });
  });

  group('videoRectIn', () {
    test('video 16:9 trong ô vuông có viền trên dưới', () {
      final r = videoRectIn(const Size(160, 160), 16 / 9);
      expect(r.width, 160);
      expect(r.height, closeTo(90, 1e-9));
      expect(r.top, closeTo(35, 1e-9));
    });
  });

  group('CameraScreen', () {
    Future<void> pumpScreen(WidgetTester tester, _FakeBackend b) async {
      // Màn dài, cần khung cao để các mục dưới ListView được dựng.
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CameraScreen(
            feeds: _feeds,
            backend: b,
            connectDelay: const Duration(milliseconds: 200),
          ),
        ),
      );
    }

    testWidgets('đang kết nối rồi có hình, hiện TRỰC TIẾP và tóm tắt người', (tester) async {
      final b = _FakeBackend(data: _lying(to: 20));
      await pumpScreen(tester, b);
      expect(find.byKey(const Key('camera-connecting')), findsOneWidget);
      expect(find.text('Đang kết nối camera…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('camera-live')), findsOneWidget);
      expect(find.byKey(const Key('camera-connecting')), findsNothing);

      b.players.last.pos = 6;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('1 người nằm'), findsOneWidget);
    });

    testWidgets('nằm lâu hiện dòng vàng, không có banner đỏ', (tester) async {
      final b = _FakeBackend(data: _lying(to: 20));
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      b.players.last.pos = 9; // sau ngưỡng 8 giây của bộ demo
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('camera-watch')), findsOneWidget);
      expect(find.textContaining('nằm khá lâu'), findsWidgets);
    });

    testWidgets('nhật ký trực tiếp: chưa tới giờ thì chưa có, video chạy tới đâu hiện tới đó', (tester) async {
      final b = _FakeBackend(data: _lying(to: 20));
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      // Mới bắt đầu: sự kiện nằm lâu (giây 8) chưa được hé lộ, cũng không có thanh dòng thời gian.
      expect(find.textContaining('nằm khá lâu'), findsNothing);
      expect(find.text('Dòng thời gian'), findsNothing);
      expect(find.byKey(const Key('camera-log')), findsOneWidget);

      b.players.last.pos = 9;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('nằm khá lâu'), findsWidgets);
    });

    testWidgets('gần giống té ngã hiện ở nhật ký, mức vàng, không có banner đỏ', (tester) async {
      final b = _FakeBackend(data: _fall());
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('gần giống té ngã'), findsNothing);
      b.players.last.pos = 3.2;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('gần giống té ngã'), findsWidgets);
      expect(find.byKey(const Key('camera-watch')), findsOneWidget);
      final banner = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(const Key('camera-urgent')), matching: find.byType(AnimatedOpacity)).first,
      );
      expect(banner.opacity, 0);
    });

    testWidgets('nút Nhận diện bật tắt', (tester) async {
      final b = _FakeBackend(data: _lying());
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nhận diện: bật'), findsOneWidget);
      await tester.tap(find.byKey(const Key('camera-detect-toggle')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nhận diện: tắt'), findsOneWidget);
    });

    testWidgets('lỗi tải video thì báo và Thử lại chạy được', (tester) async {
      final b = _FakeBackend(data: _lying(), failFirst: true);
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('camera-error')), findsOneWidget);
      expect(find.text('Chưa kết nối được camera'), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('camera-live')), findsOneWidget);
    });

    testWidgets('thiếu file nhận diện vẫn phát video, báo chưa có dữ liệu', (tester) async {
      final b = _FakeBackend();
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('camera-live')), findsOneWidget);
      expect(find.text('Chưa có dữ liệu nhận diện'), findsOneWidget);
    });

    testWidgets('đổi camera mở bộ phát mới và huỷ bộ phát cũ', (tester) async {
      final b = _FakeBackend(data: _lying());
      await pumpScreen(tester, b);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('camera-feed-b')));
      await tester.pump();
      expect(b.players.first.disposed, isTrue);
      expect(find.byKey(const Key('camera-connecting')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('camera-live')), findsOneWidget);
    });
  });

  group('CameraEntryCard', () {
    Future<void> pumpCard(WidgetTester tester, bool enabled) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [cameraEnabledProvider.overrideWith((ref) async => enabled)],
          child: const MaterialApp(home: Scaffold(body: CameraEntryCard())),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('cờ bật thì hiện thẻ Camera', (tester) async {
      await pumpCard(tester, true);
      expect(find.byKey(const Key('family-camera')), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('cờ tắt thì không hiện gì', (tester) async {
      await pumpCard(tester, false);
      expect(find.byKey(const Key('family-camera')), findsNothing);
    });
  });
}
