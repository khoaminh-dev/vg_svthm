import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client dùng chung. Chỉ đọc sau khi `Supabase.initialize` đã chạy ở main.
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);
