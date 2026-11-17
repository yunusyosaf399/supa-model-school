import 'package:flutter/foundation.dart' show kDebugMode;

/// Safe public test-project connection for local DEBUG builds.
/// Never include an elevated key or project password.
/// Release/profile builds REQUIRE explicit --dart-define values.
abstract final class SupabaseConnectionConfig {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: kDebugMode
      ? 'https://uebzvfzpbqqttbqyxxos.supabase.co'
      : '',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: kDebugMode
      ? 'sb_publishable_2MHTAn3zzA4b3lr9SIzwHg_t0R3Q9Je'
      : '',
  );

  static const usingLocalDebugDefaults = kDebugMode &&
    !bool.hasEnvironment('SUPABASE_URL') &&
    !bool.hasEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
    projectUrl.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static void validate() {
    if (projectUrl.isEmpty && publishableKey.isEmpty) return;
    final uri = Uri.tryParse(projectUrl);
    if (uri?.scheme != 'https' || uri?.host.isEmpty ||
        publishableKey.isEmpty ||
        !(publishableKey.startsWith('sb_publishable_') ||
          publishableKey.startsWith('eyJ'))) {
      throw StateError('Invalid Supabase connection configuration. '
        'Supply SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY together.');
    }
  }
}
