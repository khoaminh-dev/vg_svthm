import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/safety_repository.dart';
import '../domain/safety_models.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SupabaseSafetyRepository(ref.watch(supabaseClientProvider)),
);

final sosProvider = FutureProvider.autoDispose.family<SosEvent?, String>(
  (ref, id) => ref.watch(safetyRepositoryProvider).sos(id),
);

/// SOS đang mở của những người tôi theo dõi (hiện băng đỏ ở trang Gia đình).
final openSosProvider = FutureProvider.autoDispose<List<SosEvent>>((ref) {
  if (ref.watch(currentUserProvider.select((u) => u?.id)) == null) {
    return const <SosEvent>[];
  }
  return ref.watch(safetyRepositoryProvider).openSos();
});

final emergencyCardProvider = FutureProvider.autoDispose
    .family<EmergencyCard?, String>(
      (ref, ownerId) => ref.watch(safetyRepositoryProvider).card(ownerId),
    );
