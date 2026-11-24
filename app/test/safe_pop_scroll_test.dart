import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/core/router/routes.dart';
import 'package:vg_svthm/core/router/safe_pop.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_screen.dart';
import 'package:vg_svthm/features/voice/core/control_registry.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';

// Lỗi b51 (24/11/2026): Vy mở màn bằng router.go nên nút Quay lại (context.pop) không còn gì để thoát, người dùng bị kẹt.

VideoItem v(int n) => VideoItem(id: 'v$n', title: 'Bản tin số $n', author: 'K', thumbnailUrl: '', duration: const Duration(minutes: 10));

class _Search implements VideoSearch {
  _Search(this.items);
  final List<VideoItem> items;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async => items;
}

void main() {
  group('safePop: màn nào cũng thoát được', () {
    Widget app(GoRouter router) => MaterialApp.router(routerConfig: router);

    GoRouter make({String initial = '/'}) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
        GoRoute(
          path: '/a',
          builder: (context, _) => Scaffold(
            body: TextButton(key: const Key('back'), onPressed: () => safePop(context), child: const Text('A')),
          ),
        ),
      ],
    );

    testWidgets('mở bằng push: quay về trang trước', (t) async {
      final r = make();
      await t.pumpWidget(app(r));
      r.push('/a');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('back')));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('mở bằng go (như Vy mở màn): trước đây kẹt, giờ về Trang chủ', (t) async {
      final r = make();
      await t.pumpWidget(app(r));
      r.go('/a');
      await t.pumpAndSettle();
      expect(r.canPop(), isFalse, reason: 'ngăn xếp chỉ còn đúng màn này');
      await t.tap(find.byKey(const Key('back')));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('mở thẳng từ đường dẫn (thông báo đẩy, liên kết): cũng về Trang chủ', (t) async {
      await t.pumpWidget(app(make(initial: '/a')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('back')));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('Giải trí mở bằng giọng: nút Quay lại hoạt động', () {
    ProviderContainer make() => ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
        videoSearchProvider.overrideWithValue(_Search([for (var i = 1; i <= 8; i++) v(i)])),
      ],
    );

    Widget app(ProviderContainer c, GoRouter r) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: r),
    );

    testWidgets('go vào Giải trí rồi bấm "Quay lại" to ở đáy: về Trang chủ', (t) async {
      final c = make();
      addTearDown(c.dispose);
      final r = GoRouter(
        initialLocation: Routes.entertainment,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
          GoRoute(path: Routes.entertainment, builder: (_, _) => const EntertainmentScreen()),
        ],
      );
      await t.pumpWidget(app(c, r));
      await t.pumpAndSettle();
      expect(r.canPop(), isFalse);
      await t.tap(find.byKey(const Key('elder-back')));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('cuộn bằng giọng', () {
    Future<(ProviderContainer, ScrollController)> pumpList(WidgetTester t, {bool withScroll = true}) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: SizedBox(
              height: 600,
              child: VyControlScope(
                scroll: withScroll ? controller : null,
                child: ListView.builder(
                  controller: controller,
                  itemExtent: 100,
                  itemCount: 30,
                  itemBuilder: (_, i) => Text('mục $i'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      return (c, controller);
    }

    testWidgets('xuống, lên, về đầu, xuống cuối; ở mép thì báo ở mép', (t) async {
      final (c, ctl) = await pumpList(t);
      final reg = c.read(controlRegistryProvider);
      final view = ctl.position.viewportDimension;
      expect(reg.scroll('down'), VyScrollResult.moved);
      await t.pumpAndSettle();
      expect(ctl.offset, closeTo(view * 0.85, 1));
      expect(reg.scroll('up'), VyScrollResult.moved);
      await t.pumpAndSettle();
      expect(ctl.offset, closeTo(0, 1));
      expect(reg.scroll('up'), VyScrollResult.atEdge, reason: 'đã ở đầu');
      expect(reg.scroll('bottom'), VyScrollResult.moved);
      await t.pumpAndSettle();
      expect(ctl.offset, ctl.position.maxScrollExtent);
      expect(reg.scroll('down'), VyScrollResult.atEdge, reason: 'đã ở cuối');
      expect(reg.scroll('top'), VyScrollResult.moved);
      await t.pumpAndSettle();
      expect(ctl.offset, 0);
    });

    testWidgets('màn không đăng ký vùng cuộn: nói thật là chưa cuộn được', (t) async {
      final (c, _) = await pumpList(t, withScroll: false);
      expect(c.read(controlRegistryProvider).scroll('down'), VyScrollResult.none);
    });

    testWidgets('có hộp thoại mở thì không cuộn màn phía sau', (t) async {
      final (c, ctl) = await pumpList(t);
      final reg = c.read(controlRegistryProvider);
      final owner = Object();
      reg.set(owner, dialogId: 'dlg', dialogTitle: 'Hỏi', controls: const []);
      expect(reg.scroll('down'), VyScrollResult.none);
      expect(ctl.offset, 0);
      reg.remove(owner);
      expect(reg.scroll('down'), VyScrollResult.moved);
    });

    testWidgets('Vy cuộn rồi đọc ba bài mới, hiện số, không tự mở video nào', (t) async {
      final c = ProviderContainer(
        overrides: [routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]))],
      );
      addTearDown(c.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: SizedBox(
              height: 600,
              child: VyControlScope(
                scroll: controller,
                lists: [
                  VyList(id: 'ent.videos', title: 'Kết quả video', items: [for (var i = 1; i <= 6; i++) VyListItem(title: '🎵 Bản tin số $i #shorts', onChoose: () {})]),
                ],
                child: ListView.builder(controller: controller, itemExtent: 100, itemCount: 30, itemBuilder: (_, i) => Text('mục $i')),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      final actions = c.read(voiceActionsProvider);
      VoiceTask task(String intent, [Map<String, String> slots = const {}]) => VoiceTask(intent: intent, slots: slots);

      // "Lướt xuống để tôi xem mấy video khác": coi như hai bài đầu đã thấy, đọc bài 3, 4, 5
      final first = await actions.execute(task('scroll', {'content': 'down'}), const [], 'bác');
      await t.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(first, contains('Bài 3: Bản tin số 3'));
      expect(first, contains('Bài 5: Bản tin số 5'));
      expect(first, isNot(contains('#shorts')), reason: 'tên được làm sạch trước khi đọc');
      expect(first, contains('Bác chọn số mấy ạ?'));
      expect(c.read(videoMarksProvider), isTrue);
      expect(c.read(videoBrowseProvider), isTrue, reason: 'đang duyệt: không tự mở số 1');

      // Lướt tiếp: bài 6 là bài cuối
      final second = await actions.execute(task('scroll', {'content': 'down'}), const [], 'bác');
      expect(second, contains('Bài 6: Bản tin số 6'));
      expect(second, contains('mục cuối'));

      // Hết danh sách
      final third = await actions.execute(task('read_list'), const [], 'bác');
      expect(third, contains('hết danh sách'));
    });

    testWidgets('"đọc tên các video" đọc từ bài 1, nói tiếp thì đọc ba bài kế', (t) async {
      final c = ProviderContainer(
        overrides: [routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]))],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: VyControlScope(
              lists: [VyList(id: 'ent.videos', items: [for (var i = 1; i <= 5; i++) VyListItem(title: 'Bài hát $i', onChoose: () {})])],
              child: const SizedBox(),
            ),
          ),
        ),
      );
      final actions = c.read(voiceActionsProvider);
      final a = await actions.execute(VoiceTask(intent: 'read_list', slots: const {}), const [], 'bác');
      expect(a, startsWith('Bài 1: Bài hát 1. Bài 2: Bài hát 2. Bài 3: Bài hát 3.'));
      final b = await actions.execute(VoiceTask(intent: 'read_list', slots: const {}), const [], 'bác');
      expect(b, contains('Bài 4: Bài hát 4'));
      expect(b, contains('Bài 5: Bài hát 5'));
    });

    testWidgets('không có danh sách thì nói thật; màn không cuộn được thì nói thật', (t) async {
      final c = ProviderContainer(
        overrides: [routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]))],
      );
      addTearDown(c.dispose);
      final actions = c.read(voiceActionsProvider);
      expect(await actions.execute(VoiceTask(intent: 'read_list', slots: const {}), const [], 'bác'), contains('không thấy danh sách'));
      expect(await actions.execute(VoiceTask(intent: 'scroll', slots: const {'content': 'down'}), const [], 'bác'), contains('chưa cuộn được'));
    });
  });

  group('Giải trí: đang duyệt bằng giọng thì không tự mở video số 1', () {
    testWidgets('hiện số + đang duyệt: chờ 30 giây vẫn không mở gì', (t) async {
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final c = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
          videoSearchProvider.overrideWithValue(_Search([for (var i = 1; i <= 5; i++) v(i)])),
        ],
      );
      addTearDown(c.dispose);
      final r = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const EntertainmentScreen()),
          GoRoute(path: Routes.player, builder: (_, s) => Scaffold(body: Text('PLAYER ${(s.extra as VideoItem).id}'))),
        ],
      );
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(theme: AppTheme.light, routerConfig: r)));
      c.read(videoQueryProvider.notifier).set('nhạc xưa');
      await t.pumpAndSettle();
      c.read(videoBrowseProvider.notifier).set(true);
      c.read(videoMarksProvider.notifier).set(true);
      await t.pump();
      await t.pump(const Duration(seconds: 30));
      expect(find.textContaining('PLAYER'), findsNothing);
    });
  });
}
