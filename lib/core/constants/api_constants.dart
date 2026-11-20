
class ApiConstants {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String restBase = '$supabaseUrl/rest/v1';
}
