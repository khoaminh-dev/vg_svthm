import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import 'control_locator.dart';
import 'control_registry.dart';
import 'vy_core.dart';

/// Bề mặt vẽ con trỏ (lớp phủ). Tách ra để bộ điều khiển kiểm thử được mà không cần giao diện.
abstract class VyCursorSurface {
  Future<void> flyTo(Offset to, {required Offset from, String? label, bool instant = false, double speed = 1});
  Future<void> click();
  Future<void> glowAround(Rect r, {Duration hold});
  Future<void> hide({bool instant = false});
}

/// Điều khiển con trỏ của Vy (kế hoạch mục 7): bay tới nút, dừng một nhịp, bấm (hoặc chỉ), rồi ẩn.
///
/// Nguyên tắc:
/// - Việc bấm thật luôn đi qua hàm của điều khiển trong [ControlRegistry] (mức 3 không bao giờ bấm), con trỏ chỉ là phần nhìn.
/// - Không thấy nút thì không bay: làm thẳng.
/// - Người dùng chạm vào màn hình khi con trỏ đang chạy thì con trỏ DỪNG, KHÔNG bấm ("người dùng luôn thắng").
/// - Hệ điều hành bật "giảm chuyển động" hoặc người dùng tắt con trỏ thì nhảy thẳng/không dùng.
class VyCursorController {
  VyCursorController({
    required ControlRegistry registry,
    required ControlLocator locator,
    required VyCursorSurface? Function() surface,
    required VoidCallback onStart,
    required Offset Function() orb,
    bool Function()? reduceMotion,
    bool Function()? enabled,
    this.timeScale = 1,
  }) : _registry = registry,
       _locator = locator,
       _surface = surface,
       _onStart = onStart,
       _orb = orb,
       _reduceMotion = reduceMotion ?? (() => false),
       _enabled = enabled ?? (() => true);

  final ControlRegistry _registry;
  final ControlLocator _locator;
  final VyCursorSurface? Function() _surface;
  final VoidCallback _onStart;
  final Offset Function() _orb;
  final bool Function() _reduceMotion;
  final bool Function() _enabled;

  /// Nhân với mọi thời gian chờ (0 trong kiểm thử).
  final double timeScale;

  int _run = 0;
  bool _active = false;

  /// Đang chạy một thao tác con trỏ.
  bool get active => _active;

  Future<void> _wait(int ms) {
    final d = (ms * timeScale).round();
    return d <= 0 ? Future<void>.value() : Future<void>.delayed(Duration(milliseconds: d));
  }

  /// Người dùng chạm màn hình hoặc nói "thôi": dừng ngay tại chỗ, không bấm.
  void cancel() {
    if (!_active) return;
    _run++;
    _active = false;
    unawaited(_surface()?.hide());
  }

  void _listenTouches(void Function(PointerEvent) route, bool on) {
    try {
      final router = GestureBinding.instance.pointerRouter;
      if (on) {
        router.addGlobalRoute(route);
      } else {
        router.removeGlobalRoute(route);
      }
    } catch (_) {
      // chưa có binding (kiểm thử thuần): bỏ qua
    }
  }

  /// Kiểm tra trước khi làm: có đúng một việc làm được hay không (không bấm).
  VyInvokeResult check(String id) => _registry.check(id);

  /// Bay tới nút [id] rồi bấm (hoặc đặt công tắc [set]). Không thấy nút/không có bề mặt thì bấm thẳng.
  Future<void> press(String id, {bool? set}) async {
    final c = _registry.find(id);
    final surface = _surface();
    if (c == null || surface == null || !_enabled()) {
      _registry.invoke(id, set: set);
      return;
    }
    final run = ++_run;
    _active = true;
    void onPointer(PointerEvent e) {
      // Chỉ chạm thật của người dùng (đúng lúc ngón tay chạm xuống).
      if (e is PointerDownEvent) cancel();
    }

    _listenTouches(onPointer, true);
    try {
      _onStart(); // thu panel về thanh nhỏ để thấy màn thật
      await _wait(260);
      if (run != _run) return;
      final rect = await _locator.locate(c);
      if (run != _run) return;
      if (rect == null) {
        _active = false;
        _registry.invoke(id, set: set);
        return;
      }
      final instant = _reduceMotion();
      await surface.flyTo(
        rect.center,
        from: _orb(),
        label: _actLabel(c, set),
        instant: instant,
      );
      if (run != _run) return;
      await _wait(400); // dừng một nhịp trên nút để người xem kịp nhìn
      if (run != _run) return;
      unawaited(surface.click());
      await _wait(120);
      if (run != _run) return;
      final r = _registry.invoke(id, set: set);
      Analytics.track('vy_cursor_press', {'id': id, 'result': r.name});
      await _wait(300);
      if (run != _run) return;
      await surface.hide(instant: instant);
    } finally {
      _listenTouches(onPointer, false);
      if (run == _run) _active = false;
    }
  }

  /// "Chỉ cho bác bấm" (mức 3): bay tới nút và vẽ khung sáng, KHÔNG BẤM. Không thấy nút thì chỉ im lặng bỏ qua.
  Future<void> point(String id, {Duration hold = const Duration(milliseconds: 2400)}) async {
    final c = _registry.find(id);
    final surface = _surface();
    if (c == null || surface == null || !_enabled()) return;
    final run = ++_run;
    _active = true;
    void onPointer(PointerEvent e) {
      if (e is PointerDownEvent) cancel();
    }

    _listenTouches(onPointer, true);
    try {
      _onStart();
      await _wait(260);
      if (run != _run) return;
      final rect = await _locator.locate(c);
      if (run != _run || rect == null) return;
      final instant = _reduceMotion();
      await surface.flyTo(rect.center, from: _orb(), label: 'Bác tự bấm', instant: instant);
      if (run != _run) return;
      await surface.glowAround(rect, hold: Duration(milliseconds: (hold.inMilliseconds * timeScale).round()));
      if (run != _run) return;
      await surface.hide(instant: instant);
    } finally {
      _listenTouches(onPointer, false);
      if (run == _run) _active = false;
    }
  }

  static String _actLabel(VyControl c, bool? set) {
    if (c.kind == VyKind.toggle) return set == true ? 'Bật' : 'Tắt';
    return 'Bấm ${c.label.length > 22 ? '${c.label.substring(0, 21)}…' : c.label}';
  }
}

/// Khoá để lớp phủ con trỏ (trong `VoiceOverlay`) đăng ký bề mặt vẽ của nó.
final vyCursorSurfaceKeyProvider = Provider<GlobalKey>((ref) => GlobalKey(debugLabel: 'vy-cursor'));

final controlLocatorProvider = Provider<ControlLocator>((ref) => SemanticsControlLocator());

final vyCursorProvider = Provider<VyCursorController>((ref) {
  final key = ref.read(vyCursorSurfaceKeyProvider);
  final c = VyCursorController(
    registry: ref.read(controlRegistryProvider),
    locator: ref.read(controlLocatorProvider),
    surface: () {
      final s = key.currentState;
      return s is VyCursorSurface ? s as VyCursorSurface : null;
    },
    onStart: () => ref.read(vyCoreProvider.notifier).collapse(),
    orb: () {
      final v = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = v.physicalSize / v.devicePixelRatio;
      // Quả cầu nằm bên trái thanh Vy nhỏ ở đáy màn hình.
      return Offset(48, size.height - 96);
    },
    reduceMotion: () => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations,
  );
  return c;
});
