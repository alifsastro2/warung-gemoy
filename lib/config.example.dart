// TEMPLATE: Salin file ini menjadi config.dart dan isi dengan credentials asli kamu.
// File config.dart sudah di-gitignore dan TIDAK akan terupload ke GitHub.
// JANGAN isi credentials asli di file ini!

class Config {
  // Supabase — dapatkan dari: https://supabase.com → Project Settings → API
  static const supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
  static const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  // Google Maps SDK (untuk tampilan peta)
  // Aktifkan: Maps SDK for Android di Google Cloud Console
  static const googleMapsKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // Google Distance Matrix API (untuk hitung jarak & ongkir)
  // Aktifkan: Distance Matrix API di Google Cloud Console
  static const googleDistanceMatrixKey = 'YOUR_DISTANCE_MATRIX_API_KEY';
}
