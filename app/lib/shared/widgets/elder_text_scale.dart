import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';

/// Cỡ chữ tối thiểu cho người cao tuổi: 1,2 lần (nếu họ đã chỉnh cỡ chữ hệ thống lớn hơn thì theo đó, tối đa 1,6).
double elderScaleFor(double system) => system < 1.2 ? 1.2 : (system > 1.6 ? 1.6 : system);

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
      data: elder ? mq.copyWith(textScaler: TextScaler.linear(elderScaleFor(mq.textScaler.scale(1)))) : mq,
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SizedBox(
          height: 68,
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('elder-back'),
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_back_rounded, size: 30),
            label: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    ),
  );
}
