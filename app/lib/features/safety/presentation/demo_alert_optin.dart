import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../push/push_service.dart';

/// Tài khoản này có đang nhận cảnh báo khẩn cấp DEMO không (và nhãn để đưa cho người chạy module).
class DemoOptIn {
  const DemoOptIn({this.on = false, this.label});

  final bool on;
  final String? label;

  factory DemoOptIn.fromJson(Object? j) => j is Map
      ? DemoOptIn(on: j['on'] == true, label: j['label'] as String?)
      : const DemoOptIn();
}

/// Đọc/ghi qua máy chủ (ghi đè được khi kiểm thử).
class DemoOptInApi {
  const DemoOptInApi({required this.read, required this.write});

  final Future<DemoOptIn> Function() read;
  final Future<DemoOptIn> Function(bool on) write;
}

final demoOptInApiProvider = Provider<DemoOptInApi>((ref) {
  final c = ref.watch(supabaseClientProvider);
  return DemoOptInApi(
    read: () async => DemoOptIn.fromJson(await c.rpc('demo_alert_me')),
    write: (on) async => DemoOptIn.fromJson(await c.rpc('demo_alert_join', params: {'p_on': on})),
  );
});

/// Công tắc "Nhận cảnh báo khẩn cấp thử nghiệm" trong Cài đặt → Thông báo.
class DemoOptInNotifier extends AsyncNotifier<DemoOptIn> {
  @override
  Future<DemoOptIn> build() async {
    if (ref.watch(currentUserProvider.select((u) => u?.id)) == null) return const DemoOptIn();
    try {
      return await ref.watch(demoOptInApiProvider).read();
    } catch (_) {
      return const DemoOptIn(); // chưa chạy migration hoặc mất mạng: coi như đang tắt
    }
  }

  /// Bật/tắt. Trả null nếu thành công, hoặc thông báo lỗi để hiện cho người dùng.
  Future<String?> set(bool on) async {
    final before = state;
    state = AsyncData(DemoOptIn(on: on, label: before.value?.label));
    try {
      final r = await ref.read(demoOptInApiProvider).write(on);
      state = AsyncData(r);
      // Bật thì xin quyền thông báo và lưu mã thiết bị ngay, để máy này nhận được cảnh báo.
      if (on) unawaited(ref.read(pushServiceProvider).register());
      return null;
    } catch (_) {
      state = before;
      return 'Chưa bật được. Kiểm tra mạng rồi thử lại.';
    }
  }
}

final demoOptInProvider = AsyncNotifierProvider<DemoOptInNotifier, DemoOptIn>(DemoOptInNotifier.new);
