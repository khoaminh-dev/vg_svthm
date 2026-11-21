import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mức xác nhận của một điều khiển (khớp với phía máy chủ `ui_cmd.ts`, xem kế hoạch mục 13.3).
/// 0 làm ngay · 1 làm rồi đọc lại · 2 hỏi lại · 3 người dùng TỰ bấm (Vy không bao giờ bấm thay).
enum VyLevel {
  auto(0),
  readBack(1),
  confirm(2),
  selfOnly(3);

  const VyLevel(this.value);
  final int value;
}

enum VyKind { button, toggle, tab, field, item }

/// Một điều khiển trên màn hình mà Vy có thể nhìn thấy và (tuỳ mức) bấm giúp.
@immutable
class VyControl {
  const VyControl({
    required this.id,
    required this.label,
    this.aliases = const [],
    this.kind = VyKind.button,
    this.level = VyLevel.auto,
    this.enabled = true,
    this.value,
    this.say,
    this.onInvoke,
    this.onSet,
  });

  /// Mã ổn định, dạng `màn.việc` (ví dụ `meds.taken`). Máy chủ chỉ làm việc với mã được gửi lên.
  final String id;

  /// Nhãn đúng như người dùng đọc thấy trên nút.
  final String label;

  /// Cách gọi khác người dùng hay nói ("tôi uống rồi"). Có dấu; máy chủ tự bỏ dấu để so.
  final List<String> aliases;
  final VyKind kind;
  final VyLevel level;
  final bool enabled;

  /// Công tắc: đang bật hay tắt.
  final bool? value;

  /// Câu Vy nói sau khi bấm xong ("Dạ, con ghi bác đã uống rồi ạ.").
  final String? say;

  /// Việc làm khi Vy "bấm": nút, thẻ, tab.
  final VoidCallback? onInvoke;

  /// Công tắc: đặt giá trị mong muốn (true = bật).
  final ValueChanged<bool>? onSet;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (aliases.isNotEmpty) 'aliases': aliases,
    'kind': kind.name,
    'level': level.value,
    'enabled': enabled,
    if (value != null) 'value': value,
    if (say != null) 'say': say,
  };
}

/// Một mục trong danh sách có đánh số (kết quả video, ...).
@immutable
class VyListItem {
  const VyListItem({required this.title, required this.onChoose});

  final String title;
  final VoidCallback onChoose;
}

/// Danh sách đang hiện, Vy đọc "một, hai, ba…" và người dùng chọn theo số.
@immutable
class VyList {
  const VyList({required this.id, required this.items, this.title = ''});

  final String id;
  final String title;
  final List<VyListItem> items;

  Map<String, Object?> toJson() => {
    'id': id,
    if (title.isNotEmpty) 'title': title,
    'items': [
      for (var i = 0; i < items.length && i < 10; i++)
        {'n': i + 1, 'title': items[i].title},
    ],
  };
}

/// Khai báo của một "chủ" (màn hình hoặc hộp thoại) trong sổ.
class _Entry {
  _Entry({
    required this.seq,
    required this.controls,
    required this.lists,
    required this.dialogId,
    required this.dialogTitle,
  });

  final int seq;
  final List<VyControl> controls;
  final List<VyList> lists;
  final String? dialogId;
  final String? dialogTitle;

  bool get isDialog => dialogId != null;
}

/// Kết quả của việc bấm một điều khiển theo mã.
enum VyInvokeResult { done, notFound, disabled, selfOnly }

/// Sổ đăng ký điều khiển: các màn hình/hộp thoại khai báo cái gì đang hiện; Vy đọc ảnh chụp gửi lên não
/// và bấm theo mã khi não trả về. Chỉ chủ đang ở trên cùng (không bị màn khác che) mới có mặt trong sổ.
class ControlRegistry {
  final _entries = <Object, _Entry>{};
  int _seq = 0;

  /// Đăng ký hoặc cập nhật khai báo của [owner]. Gọi lại với cùng [owner] thì thay thế.
  void set(
    Object owner, {
    List<VyControl> controls = const [],
    List<VyList> lists = const [],
    String? dialogId,
    String? dialogTitle,
  }) {
    final old = _entries[owner];
    _entries[owner] = _Entry(
      seq: old?.seq ?? ++_seq,
      controls: controls,
      lists: lists,
      dialogId: dialogId,
      dialogTitle: dialogTitle,
    );
  }

  void remove(Object owner) => _entries.remove(owner);

  /// Đang có hộp thoại (có khai báo) hiện trên màn: Vy tự nhắc không được bật lên che nút của hộp thoại.
  bool get hasDialog => _topDialog != null;

  _Entry? get _topDialog {
    _Entry? top;
    for (final e in _entries.values) {
      if (e.isDialog && (top == null || e.seq > top.seq)) top = e;
    }
    return top;
  }

  List<_Entry> get _screens => [
    for (final e in _entries.values)
      if (!e.isDialog) e,
  ]..sort((a, b) => a.seq.compareTo(b.seq));

  /// Các điều khiển người dùng đang thấy trên màn (không tính hộp thoại).
  List<VyControl> get controls => [for (final e in _screens) ...e.controls];

  List<VyList> get lists => [for (final e in _screens) ...e.lists];

  /// Tìm điều khiển đang với tới được (hộp thoại che màn sau) theo mã.
  VyControl? find(String id) => _find(id);

  /// Kiểm tra bấm được hay không, KHÔNG bấm: dùng để quyết định nói gì trước khi con trỏ bay.
  VyInvokeResult check(String id) {
    final c = _find(id);
    if (c == null) return VyInvokeResult.notFound;
    if (c.level == VyLevel.selfOnly) return VyInvokeResult.selfOnly;
    if (!c.enabled) return VyInvokeResult.disabled;
    if (c.onInvoke == null && c.onSet == null) return VyInvokeResult.notFound;
    return VyInvokeResult.done;
  }

  VyControl? _find(String id) {
    final d = _topDialog;
    // Có hộp thoại: chỉ với tới nút của hộp thoại (màn phía sau bị che).
    final pool = d != null ? d.controls : controls;
    for (final c in pool) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Ảnh chụp để gửi lên não (`ui.context`). Dữ liệu nhỏ gọn, chỉ nhãn nút và tiêu đề mục.
  Map<String, Object?> snapshot({
    required String role,
    required String route,
    bool playerOpen = false,
    bool playerPlaying = false,
  }) {
    final d = _topDialog;
    return {
      'role': role,
      'route': route,
      'dialog': d == null
          ? null
          : {
              'id': d.dialogId,
              'title': d.dialogTitle ?? '',
              'controls': [for (final c in d.controls) c.toJson()],
            },
      'controls': [for (final c in controls.take(60)) c.toJson()],
      'lists': [for (final l in lists.take(3)) l.toJson()],
      'player': {'open': playerOpen, 'playing': playerPlaying},
    };
  }

  /// Bấm điều khiển theo mã. Kiểm tra lại ở app (không tin hoàn toàn máy chủ): mức 3 không bao giờ được bấm.
  VyInvokeResult invoke(String id, {bool? set}) {
    final c = _find(id);
    if (c == null) return VyInvokeResult.notFound;
    if (c.level == VyLevel.selfOnly) return VyInvokeResult.selfOnly;
    if (!c.enabled) return VyInvokeResult.disabled;
    if (c.kind == VyKind.toggle && set != null && c.onSet != null) {
      c.onSet!(set);
      return VyInvokeResult.done;
    }
    final f = c.onInvoke;
    if (f == null) return VyInvokeResult.notFound;
    f();
    return VyInvokeResult.done;
  }

  /// Chọn mục thứ [n] (bắt đầu từ 1) của danh sách [listId].
  bool choose(String listId, int n) {
    if (_topDialog != null) return false;
    for (final l in lists) {
      if (l.id == listId && n >= 1 && n <= l.items.length) {
        l.items[n - 1].onChoose();
        return true;
      }
    }
    return false;
  }
}

final controlRegistryProvider = Provider<ControlRegistry>((ref) => ControlRegistry());

/// Khai báo điều khiển/danh sách của một màn hình hoặc hộp thoại trong phạm vi [child].
/// Chỉ có mặt trong sổ khi đang ở trên cùng: màn bị màn khác (hoặc hộp thoại) che, hoặc tab đang ẩn thì tự rút khỏi sổ.
class VyControlScope extends ConsumerStatefulWidget {
  const VyControlScope({
    super.key,
    this.controls = const [],
    this.lists = const [],
    this.dialogId,
    this.dialogTitle,
    required this.child,
  });

  final List<VyControl> controls;
  final List<VyList> lists;

  /// Đặt khi đây là hộp thoại: các điều khiển của nó che màn phía sau.
  final String? dialogId;
  final String? dialogTitle;
  final Widget child;

  @override
  ConsumerState<VyControlScope> createState() => _VyControlScopeState();
}

class _VyControlScopeState extends ConsumerState<VyControlScope> {
  final _owner = Object();
  ControlRegistry? _registry;

  bool _active(BuildContext context) {
    final route = ModalRoute.of(context);
    final current = route?.isCurrent ?? true;
    return current && TickerMode.of(context);
  }

  void _sync(BuildContext context) {
    final ControlRegistry r = ref.read(controlRegistryProvider);
    _registry = r;
    if (_active(context)) {
      r.set(
        _owner,
        controls: widget.controls,
        lists: widget.lists,
        dialogId: widget.dialogId,
        dialogTitle: widget.dialogTitle,
      );
    } else {
      r.remove(_owner);
    }
  }

  @override
  void dispose() {
    _registry?.remove(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cập nhật sổ ngay trong lúc dựng: sổ là một đối tượng thường (không phải provider) nên không gây dựng lại.
    _sync(context);
    return widget.child;
  }
}
