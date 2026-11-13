import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/update_repository.dart';
import '../domain/app_update.dart';

final updateRepositoryProvider = Provider<UpdateRepository>((ref) => UpdateRepository(ref.watch(supabaseClientProvider)));

final apkInstallerProvider = Provider<ApkInstaller>((ref) => OtaApkInstaller());

/// Kiểm tra một lần khi mở app.
final updateCheckProvider = FutureProvider<AppUpdate?>((ref) => ref.watch(updateRepositoryProvider).check());

/// Người dùng đã bấm "Để sau" ở bản nhắc nhẹ (chỉ trong lần mở app này).
class UpdateDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final updateDismissedProvider = NotifierProvider<UpdateDismissed, bool>(UpdateDismissed.new);
