import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../safety/domain/safety_models.dart' show dialable;
import '../../safety/presentation/sos_widgets.dart' show phoneLauncherProvider;

const _channel = MethodChannel('vg.call');

/// Gọi thẳng một số điện thoại: lần đầu xin quyền (người dùng cho phép thì gọi luôn).
/// Máy không có điện thoại, từ chối quyền hoặc lỗi kênh thì mở bàn phím gọi có số điền sẵn.
/// CHỈ gọi với số đã được người dùng thấy trên thẻ đếm ngược (người liên hệ trong thẻ y tế hoặc 115).
typedef DirectCall = Future<void> Function(String number);

final directCallProvider = Provider<DirectCall>((ref) {
  final dial = ref.read(phoneLauncherProvider);
  return (String number) async {
    final n = dialable(number);
    if (!RegExp(r'^\+?[0-9]{3,16}$').hasMatch(n)) return; // không gọi số lạ
    try {
      final r = await _channel.invokeMethod<String>('call', {'number': n});
      if (r == 'no_telephony' || r == null) await dial(n);
    } on MissingPluginException {
      await dial(n);
    } on PlatformException {
      await dial(n);
    }
  };
});
