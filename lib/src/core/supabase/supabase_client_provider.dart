import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Null when the app was intentionally started without Supabase Dart defines.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
