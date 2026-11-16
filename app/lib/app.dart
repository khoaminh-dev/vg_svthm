import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/analytics/analytics.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/update/presentation/update_gate.dart';
import 'shared/widgets/logo_intro.dart';
import 'features/voice/presentation/voice_overlay.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mọi sự kiện thống kê kèm vai trò hiện tại.
    Analytics.role = ref.watch(currentUserProvider.select((u) => u?.role?.code));
    return MaterialApp.router(
      title: 'Viegrand',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => LogoIntro(
        child: UpdateGate(
          child: VoiceOverlay(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
