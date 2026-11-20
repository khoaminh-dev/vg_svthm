import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/features/voice/core/control_registry.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';

void main() {
  group('ControlRegistry', () {
    test('ảnh chụp gửi lên não: nhãn, mức, giá trị công tắc, danh sách có số', () {
      final r = ControlRegistry();
      final owner = Object();
      r.set(
        owner,
        controls: [
          VyControl(id: 'a', label: 'Đã uống', aliases: const ['tôi uống rồi'], level: VyLevel.readBack, say: 'Dạ'),
          VyControl(id: 'b', label: 'Hiện chữ', kind: VyKind.toggle, value: true, onSet: (_) {}),
          const VyControl(id: 'c', label: 'Đăng xuất', level: VyLevel.selfOnly),
        ],
        lists: [
          VyList(id: 'l', title: 'Video', items: [
            for (var i = 0; i < 14; i++) VyListItem(title: 'Bài $i', onChoose: () {}),
          ]),
        ],
      );
      final s = r.snapshot(role: 'elder', route: '/meds', playerOpen: true);
      expect(s['role'], 'elder');
      expect(s['route'], '/meds');
      expect(s['dialog'], isNull);
      final controls = s['controls']! as List;
      expect(controls.length, 3);
      expect((controls[0] as Map)['level'], 1);
      expect((controls[0] as Map)['aliases'], ['tôi uống rồi']);
      expect((controls[1] as Map)['value'], true);
      expect((controls[1] as Map)['kind'], 'toggle');
      expect((controls[2] as Map)['level'], 3);
      final lists = s['lists']! as List;
      expect(((lists[0] as Map)['items'] as List).length, 10); // tối đa 10 mục
      expect(((lists[0] as Map)['items'] as List).first, {'n': 1, 'title': 'Bài 0'});
      expect((s['player']! as Map)['open'], true);
    });

    test('mức 3 không bao giờ được bấm; nút tắt báo disabled; không có mã thì notFound', () {
      final r = ControlRegistry();
      var hit = 0;
      r.set(Object(), controls: [
        VyControl(id: 'logout', label: 'Đăng xuất', level: VyLevel.selfOnly, onInvoke: () => hit++),
        VyControl(id: 'undo', label: 'Hoàn tác', enabled: false, onInvoke: () => hit++),
        VyControl(id: 'ok', label: 'Đã uống', onInvoke: () => hit++),
      ]);
      expect(r.invoke('logout'), VyInvokeResult.selfOnly);
      expect(r.invoke('undo'), VyInvokeResult.disabled);
      expect(r.invoke('nope'), VyInvokeResult.notFound);
      expect(hit, 0);
      expect(r.invoke('ok'), VyInvokeResult.done);
      expect(hit, 1);
    });

    test('công tắc: set(true/false) gọi onSet với đúng giá trị', () {
      final r = ControlRegistry();
      final got = <bool>[];
      r.set(Object(), controls: [
        VyControl(id: 't', label: 'Chữ', kind: VyKind.toggle, value: true, onSet: got.add),
      ]);
      expect(r.invoke('t', set: false), VyInvokeResult.done);
      expect(r.invoke('t', set: true), VyInvokeResult.done);
      expect(got, [false, true]);
    });

    test('hộp thoại che màn phía sau: chỉ với tới nút của hộp thoại', () {
      final r = ControlRegistry();
      var screen = 0, stay = 0;
      r.set(Object(), controls: [VyControl(id: 'home.meds', label: 'Thuốc', onInvoke: () => screen++)]);
      final dlg = Object();
      r.set(dlg, dialogId: 'dlg', dialogTitle: 'Đăng xuất?', controls: [
        VyControl(id: 'stay', label: 'Ở lại', onInvoke: () => stay++),
        const VyControl(id: 'ok', label: 'Đăng xuất', level: VyLevel.selfOnly),
      ]);
      final s = r.snapshot(role: 'elder', route: '/profile');
      expect((s['dialog']! as Map)['id'], 'dlg');
      expect(r.invoke('home.meds'), VyInvokeResult.notFound); // màn sau bị che
      expect(screen, 0);
      expect(r.invoke('ok'), VyInvokeResult.selfOnly);
      expect(r.invoke('stay'), VyInvokeResult.done);
      expect(stay, 1);
      r.remove(dlg);
      expect(r.invoke('home.meds'), VyInvokeResult.done);
      expect(r.snapshot(role: 'elder', route: '/')['dialog'], isNull);
    });

    test('chọn theo số: đúng mục; số quá cỡ hoặc đang có hộp thoại thì không chọn', () {
      final r = ControlRegistry();
      final picked = <int>[];
      r.set(Object(), lists: [
        VyList(id: 'v', items: [
          for (var i = 1; i <= 3; i++) VyListItem(title: 'B$i', onChoose: () => picked.add(i)),
        ]),
      ]);
      expect(r.choose('v', 2), isTrue);
      expect(r.choose('v', 4), isFalse);
      expect(r.choose('v', 0), isFalse);
      expect(r.choose('khac', 1), isFalse);
      r.set(Object(), dialogId: 'd');
      expect(r.choose('v', 1), isFalse);
      expect(picked, [2]);
    });

    test('hai chủ cùng khai báo thì điều khiển của cả hai đều có mặt; chủ rút đi thì mất', () {
      final r = ControlRegistry();
      final a = Object(), b = Object();
      r.set(a, controls: [const VyControl(id: 'x', label: 'X')]);
      r.set(b, controls: [const VyControl(id: 'y', label: 'Y')]);
      expect(r.controls.map((c) => c.id), ['x', 'y']);
      r.set(a, controls: [const VyControl(id: 'x2', label: 'X2')]); // cập nhật chỗ cũ, giữ thứ tự
      expect(r.controls.map((c) => c.id), ['x2', 'y']);
      r.remove(a);
      expect(r.controls.map((c) => c.id), ['y']);
    });
  });

  group('VyControlScope (trên cây giao diện)', () {
    Future<ControlRegistry> pump(WidgetTester t, Widget home) async {
      final r = ControlRegistry();
      await t.pumpWidget(
        ProviderScope(
          overrides: [controlRegistryProvider.overrideWithValue(r)],
          child: MaterialApp(home: home),
        ),
      );
      return r;
    }

    testWidgets('có mặt khi đang ở trên cùng, rút đi khi bị màn khác che và quay lại khi màn trên đóng', (t) async {
      final r = ControlRegistry();
      late BuildContext homeCtx;
      await t.pumpWidget(
        ProviderScope(
          overrides: [controlRegistryProvider.overrideWithValue(r)],
          child: MaterialApp(
            home: Builder(builder: (c) {
              homeCtx = c;
              return const VyControlScope(
                controls: [VyControl(id: 'home.a', label: 'A')],
                child: Scaffold(body: Text('trang chủ')),
              );
            }),
          ),
        ),
      );
      await t.pump();
      expect(r.controls.map((c) => c.id), ['home.a']);

      // Đẩy một màn khác lên trên: màn dưới không còn thấy được.
      Navigator.of(homeCtx).push(MaterialPageRoute<void>(
        builder: (_) => const VyControlScope(
          controls: [VyControl(id: 'next.b', label: 'B')],
          child: Scaffold(body: Text('màn hai')),
        ),
      ));
      await t.pumpAndSettle();
      expect(r.controls.map((c) => c.id), ['next.b']);

      Navigator.of(homeCtx).pop();
      await t.pumpAndSettle();
      expect(r.controls.map((c) => c.id), ['home.a']);
    });

    testWidgets('hộp thoại đang mở: nút của hộp thoại là "dialog", màn sau tạm rút', (t) async {
      final r = ControlRegistry();
      late BuildContext c0;
      await t.pumpWidget(
        ProviderScope(
          overrides: [controlRegistryProvider.overrideWithValue(r)],
          child: MaterialApp(
            home: Builder(builder: (c) {
              c0 = c;
              return const VyControlScope(
                controls: [VyControl(id: 'p.toggle', label: 'Chữ')],
                child: Scaffold(body: Text('hồ sơ')),
              );
            }),
          ),
        ),
      );
      await t.pump();
      showDialog<void>(
        context: c0,
        builder: (ctx) => VyControlScope(
          dialogId: 'dlg',
          dialogTitle: 'Hỏi',
          controls: [VyControl(id: 'dlg.no', label: 'Không', onInvoke: () => Navigator.pop(ctx))],
          child: const AlertDialog(title: Text('Hỏi')),
        ),
      );
      await t.pumpAndSettle();
      final s = r.snapshot(role: 'elder', route: '/');
      expect((s['dialog']! as Map)['id'], 'dlg');
      expect(s['controls'], isEmpty); // màn sau đã rút khỏi sổ
      expect(r.invoke('dlg.no'), VyInvokeResult.done);
      await t.pumpAndSettle();
      expect(r.snapshot(role: 'elder', route: '/')['dialog'], isNull);
      expect(r.controls.map((c) => c.id), ['p.toggle']);
    });

    testWidgets('tab đang ẩn (TickerMode tắt) không khai báo', (t) async {
      final r = await pump(
        t,
        TickerMode(
          enabled: false,
          child: const VyControlScope(
            controls: [VyControl(id: 'hidden', label: 'Ẩn')],
            child: SizedBox(),
          ),
        ),
      );
      await t.pump();
      expect(r.controls, isEmpty);
    });

    testWidgets('gỡ widget thì rút khỏi sổ; đổi giá trị công tắc thì sổ cập nhật', (t) async {
      final r = ControlRegistry();
      final flag = ValueNotifier<bool>(true);
      await t.pumpWidget(
        ProviderScope(
          overrides: [controlRegistryProvider.overrideWithValue(r)],
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: flag,
              builder: (_, v, _) => VyControlScope(
                controls: [VyControl(id: 't', label: 'Chữ', kind: VyKind.toggle, value: v)],
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      expect(r.controls.single.value, true);
      flag.value = false;
      await t.pump();
      expect(r.controls.single.value, false);
      await t.pumpWidget(const SizedBox());
      expect(r.controls, isEmpty);
    });
  });

  group('VoiceActions: bấm điều khiển theo mã máy chủ trả về', () {
    ProviderContainer make(ControlRegistry reg) {
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]);
      return ProviderContainer(overrides: [
        controlRegistryProvider.overrideWithValue(reg),
        routerProvider.overrideWithValue(router),
      ]);
    }

    VoiceTask task(String intent, Map<String, String> slots) => VoiceTask(intent: intent, slots: slots);

    test('invoke_control: bấm đúng nút, mức 3 và nút lạ có câu nói riêng', () async {
      final reg = ControlRegistry();
      var taken = 0;
      bool? set;
      reg.set(Object(), controls: [
        VyControl(id: 'meds.taken', label: 'Đã uống', onInvoke: () => taken++),
        VyControl(id: 'prof.captions', label: 'Chữ', kind: VyKind.toggle, value: true, onSet: (v) => set = v),
        const VyControl(id: 'prof.logout', label: 'Đăng xuất', level: VyLevel.selfOnly),
      ]);
      final c = make(reg);
      addTearDown(c.dispose);
      final a = c.read(voiceActionsProvider);
      expect(await a.execute(task('invoke_control', {'control_id': 'meds.taken'}), const [], 'bác'), isNull);
      expect(taken, 1);
      expect(await a.execute(task('invoke_control', {'control_id': 'prof.captions', 'set': '0'}), const [], 'bác'), isNull);
      expect(set, false);
      final self = await a.execute(task('invoke_control', {'control_id': 'prof.logout'}), const [], 'bác');
      expect(self, contains('tự bấm'));
      final lost = await a.execute(task('invoke_control', {'control_id': 'khong.co'}), const [], 'bác');
      expect(lost, contains('chưa thấy'));
    });

    test('choose_item: chọn đúng mục, sai số thì báo', () async {
      final reg = ControlRegistry();
      final picked = <int>[];
      reg.set(Object(), lists: [
        VyList(id: 'ent.videos', items: [
          for (var i = 1; i <= 5; i++) VyListItem(title: 'B$i', onChoose: () => picked.add(i)),
        ]),
      ]);
      final c = make(reg);
      addTearDown(c.dispose);
      final a = c.read(voiceActionsProvider);
      expect(await a.execute(task('choose_item', {'list_id': 'ent.videos', 'n': '3'}), const [], 'bác'), isNull);
      expect(picked, [3]);
      final bad = await a.execute(task('choose_item', {'list_id': 'ent.videos', 'n': '9'}), const [], 'bác');
      expect(bad, contains('chưa chọn được'));
    });
  });
}
