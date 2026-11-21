import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/features/voice/core/vy_settings.dart';

void main() {
  test('ô gõ chữ cho Vy: mặc định TẮT, bật được và nhớ lại', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect((await c.read(vySettingsProvider.future)).textInput, isFalse);
    await c.read(vySettingsProvider.notifier).setTextInput(true);
    expect(c.read(vySettingsProvider).value!.textInput, isTrue);

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect((await c2.read(vySettingsProvider.future)).textInput, isTrue);
  });
}
