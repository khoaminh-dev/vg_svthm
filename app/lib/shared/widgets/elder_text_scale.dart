import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/domain/auth_user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';

/// Cỡ chữ tối thiểu cho người cao tuổi: 1,2 lần (nếu họ đã chỉnh cỡ chữ hệ thống lớn hơn thì theo đó, tối đa 1,6).
double elderScaleFor(double system) => system < 1.2 ? 1.2 : (system > 1.6 ? 1.6 : system);

/// Người dùng nhờ Vy "tăng/giảm cỡ chữ": cộng thêm vào cỡ chữ của người cao tuổi, mỗi bước 0,15, tổng từ 1,0 đến 2,0.
class ElderTextBoostNotifier extends Notifier<double> {
  static const _key = 'elder_text_boost';
  static const step = 0.15;
  static const minTotal = 1.0;
  static const maxTotal = 2.0;

  @override
  double build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(_key);
      if (v != null) state = v.clamp(-0.5, 0.8);
    } catch (_) {}
  }

  /// Đổi một bước theo cỡ chữ hệ thống [system]; trả về false nếu đã chạm mức tối đa/tối thiểu.
  bool bump(int direction, double system) {
    final base = elderScaleFor(system);
    final next = (base + state + direction * step);
    if (next > maxTotal + 0.001 || next < minTotal - 0.001) return false;
    state = double.parse((state + direction * step).toStringAsFixed(2));
    () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setDouble(_key, state);
      } catch (_) {}
    }();
    return true;
  }
}

final elderTextBoostProvider = NotifierProvider<ElderTextBoostNotifier, double>(ElderTextBoostNotifier.new);

/// Bọc cả app: người cao tuổi thấy chữ to hơn ở mọi màn (kể cả các màn mở chồng lên như Cộng đồng, Giải trí, phòng chat).
/// Những màn tự căn cỡ (trang chủ, camera đo, SOS) bọc thêm [ElderScaleReset] để trở về cỡ chữ hệ thống.
class ElderTextScale extends ConsumerWidget {
  const ElderTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elder = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;
    final mq = MediaQuery.of(context);
    // Luôn bọc bằng MediaQuery (kể cả không phải người cao tuổi) để cấu trúc cây không đổi khi đổi vai trò,
    // nếu không Navigator bị dựng lại giữa chừng.
    return MediaQuery(
      data: elder
          ? mq.copyWith(
              textScaler: TextScaler.linear(
                (elderScaleFor(mq.textScaler.scale(1)) + ref.watch(elderTextBoostProvider)).clamp(ElderTextBoostNotifier.minTotal, ElderTextBoostNotifier.maxTotal),
              ),
            )
          : mq,
      child: child,
    );
  }
}

/// Trả cỡ chữ về đúng cỡ hệ thống cho một màn tự căn cỡ.
class ElderScaleReset extends StatelessWidget {
  const ElderScaleReset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: MediaQueryData.fromView(View.of(context)).textScaler),
    child: child,
  );
}

/// Thanh "Quay lại" to ở đáy cho người cao tuổi trên màn mở chồng; người khác không có (null).
Widget? elderBackBar(BuildContext context, WidgetRef ref) =>
    ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder
        ? ElderBackBar(onPressed: () => Navigator.of(context).maybePop())
        : null;

/// Thanh dưới có một nút "Quay lại" thật to, cho các màn người cao tuổi mở chồng lên (Cộng đồng, Giải trí).
class ElderBackBar extends StatelessWidget {
  const ElderBackBar({super.key, required this.onPressed, this.label = 'Quay lại'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        // Chừa chỗ bên phải cho nút Vy nổi để không đè lên nút Quay lại.
        padding: const EdgeInsets.fromLTRB(16, 10, 112, 10),
        child: SizedBox(
          height: 68,
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('elder-back'),
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_back_rounded, size: 30),
            label: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ),
  );
}
