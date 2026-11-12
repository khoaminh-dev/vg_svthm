import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/supabase_bp_repository.dart';
import '../../domain/bp_models.dart';
import '../../domain/bp_repository.dart';

final bpRepositoryProvider = Provider<BpRepository>(
  (ref) => SupabaseBpRepository(ref.watch(supabaseClientProvider)),
);

/// Lịch sử đo huyết áp (mới nhất trước).
final bpReadingsProvider = FutureProvider.autoDispose<List<BpReading>>(
  (ref) => ref.watch(bpRepositoryProvider).list(),
);
