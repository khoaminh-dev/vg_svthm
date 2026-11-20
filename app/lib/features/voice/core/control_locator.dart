import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'control_registry.dart';
import 'vi_text.dart';

/// Tìm vị trí (hình chữ nhật, toạ độ logic) của một điều khiển trên màn hình để con trỏ bay tới.
/// Chỉ dùng để chỉ cho đẹp và cho người dùng thấy: việc bấm thật đi qua hàm của điều khiển trong [ControlRegistry].
abstract class ControlLocator {
  /// Null nếu không thấy nút (khi đó Vy làm thẳng, không bay).
  Future<Rect?> locate(VyControl control);
}

String _nz(String s) => viNorm(s);

/// Một nút/chữ trong cây trợ năng.
class SemNode {
  const SemNode({required this.id, required this.label, required this.rect, required this.canTap, required this.button});

  final int id;
  final String label;
  final Rect rect;
  final bool canTap;
  final bool button;
}

/// Chọn nút khớp nhất với điều khiển trong danh sách [nodes]. Thuần (kiểm thử được).
///
/// Khớp khi nhãn trợ năng bằng nhãn/từ đồng nghĩa của điều khiển, hoặc là một phần nguyên vẹn của nhãn điều khiển
/// ("Đã uống" trên nút khi điều khiển tên "Đã uống Túi Tối"). Ưu tiên nút chạm được, rồi nút có nhãn dài (cụ thể) hơn.
SemNode? bestMatch(VyControl c, List<SemNode> nodes) {
  final names = [c.label, ...c.aliases].map(_nz).where((s) => s.isNotEmpty).toList();
  if (names.isEmpty) return null;
  SemNode? best;
  var bestScore = 0.0;
  for (final n in nodes) {
    if (n.rect.width < 8 || n.rect.height < 8) continue;
    final l = _nz(n.label);
    if (l.isEmpty) continue;
    var s = 0.0;
    for (final name in names) {
      if (l == name) {
        s = 3;
        break;
      }
      if (l.length >= 3 && ' $name '.contains(' $l ')) s = s < 2 ? 2 : s;
      if (name.length >= 3 && ' $l '.contains(' $name ')) s = s < 1.5 ? 1.5 : s;
    }
    if (s == 0) continue;
    if (n.canTap || n.button) s += 0.5;
    s += l.length / 1000; // nhãn dài (cụ thể) hơn thắng khi hoà
    if (s > bestScore) {
      bestScore = s;
      best = n;
    }
  }
  return best;
}

/// Bộ định vị thật bằng cây trợ năng của Flutter (đã kiểm chứng ở Giai đoạn 0: 16 điều khiển trong ~14 ms).
class SemanticsControlLocator implements ControlLocator {
  SemanticsHandle? _handle;

  SemanticsOwner? get _owner {
    for (final v in RendererBinding.instance.renderViews) {
      final o = v.owner?.semanticsOwner;
      if (o != null) return o;
    }
    return null;
  }

  Rect _globalRect(SemanticsNode node) {
    var r = node.rect;
    SemanticsNode? n = node;
    while (n != null) {
      final t = n.transform;
      if (t != null) r = MatrixUtils.transformRect(t, r);
      n = n.parent;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final d = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    return Rect.fromLTRB(r.left / d, r.top / d, r.right / d, r.bottom / d);
  }

  List<SemNode> _snapshot() {
    final root = _owner?.rootSemanticsNode;
    if (root == null) return const [];
    final out = <SemNode>[];
    void visit(SemanticsNode n) {
      if (!n.isInvisible) {
        final d = n.getSemanticsData();
        final label = d.label.replaceAll('\n', ' ').trim();
        final canTap = d.hasAction(SemanticsAction.tap);
        if (label.isNotEmpty && !d.flagsCollection.isHidden) {
          out.add(SemNode(id: n.id, label: label, rect: _globalRect(n), canTap: canTap, button: d.flagsCollection.isButton));
        }
      }
      n.visitChildren((c) {
        visit(c);
        return true;
      });
    }

    visit(root);
    return out;
  }

  Future<List<SemNode>> _snapshotAsync() async {
    // Cây trợ năng bật lần đầu cần ít nhất một khung hình.
    for (var i = 0; i < 4; i++) {
      final l = _snapshot();
      if (l.isNotEmpty) return l;
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    return const [];
  }

  @override
  Future<Rect?> locate(VyControl control) async {
    // Bật cây trợ năng chỉ trong lúc tìm (tốn CPU), rồi tắt.
    _handle ??= SemanticsBinding.instance.ensureSemantics();
    try {
      var nodes = await _snapshotAsync();
      var hit = bestMatch(control, nodes);
      if (hit == null) return null;
      final screen = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
          WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      // Nút nằm ngoài màn hình: nhờ cây trợ năng đưa vào màn hình rồi tìm lại một lần.
      if (hit.rect.bottom > screen.height || hit.rect.top < 0) {
        _owner?.performAction(hit.id, SemanticsAction.showOnScreen);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        nodes = await _snapshotAsync();
        hit = bestMatch(control, nodes);
        if (hit == null) return null;
      }
      return hit.rect;
    } finally {
      _handle?.dispose();
      _handle = null;
    }
  }
}
