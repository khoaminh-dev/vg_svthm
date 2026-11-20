import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/analytics/analytics.dart';
import 'core/config/env.dart';
import 'core/diagnostics/app_trace.dart';
import 'features/push/push_service.dart';
import 'shared/widgets/config_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const MaterialApp(home: ConfigErrorScreen()));
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  Analytics.init();
  await AppTrace.init();
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    AppTrace.line('LỖI FLUTTER: ${details.exception}\n${details.stack}');
    Analytics.trackError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppTrace.line('LỖI NỀN: $error\n$stack');
    Analytics.trackError(error, stack);
    return true;
  };
  final container = ProviderContainer();
  runApp(UncontrolledProviderScope(container: container, child: const App()));
  // Thông báo đẩy khởi động sau khi giao diện lên, không làm chậm lúc mở app.
  unawaited(container.read(pushServiceProvider).start());
}
