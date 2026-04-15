import 'package:shared_preferences/shared_preferences.dart';

/// Centralized configuration for the ASNG Face Recognition Kiosk App.
/// All settings are persisted via SharedPreferences so they survive app restarts.
/// Admin/technician can update these values via the hidden Settings screen.
class AppConfig {
  // ── SharedPreferences Keys ──
  static const String _keyBaseUrl = 'base_url';
  static const String _keyDeviceSn = 'device_sn';

  // ── Default Values ──
  static const String defaultBaseUrl = 'http://192.168.100.57:5000';
  static const String defaultDeviceSn = 'WEB_APP_01';

  // ── Endpoint Constants ──
  static const String predictEndpoint = '/api/predict';
  static const String registerEndpoint = '/api/register';

  // ── Getters ──

  /// Returns the full base URL (e.g., "http://192.168.100.57:5000")
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl) ?? defaultBaseUrl;
  }

  /// Returns the device serial number (e.g., "KIOSK_DUKCAPIL_01")
  static Future<String> getDeviceSn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceSn) ?? defaultDeviceSn;
  }

  // ── Setters ──

  /// Saves the base URL to persistent storage
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }

  /// Saves the device serial number to persistent storage
  static Future<void> setDeviceSn(String sn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceSn, sn);
  }

  // ── Helpers ──

  /// Returns the full predict API URL (baseUrl + endpoint)
  static Future<String> getPredictUrl() async {
    final base = await getBaseUrl();
    return '$base$predictEndpoint';
  }

  /// Returns the full register API URL (baseUrl + endpoint)
  static Future<String> getRegisterUrl() async {
    final base = await getBaseUrl();
    return '$base$registerEndpoint';
  }
}
