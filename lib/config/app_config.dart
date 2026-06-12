import 'package:shared_preferences/shared_preferences.dart';

/// Centralized configuration for the ASNG Face Recognition Kiosk App.
/// All settings are persisted via SharedPreferences so they survive app restarts.
/// Admin/technician can update these values via the hidden Settings screen.
class AppConfig {
  // ── SharedPreferences Keys ──
  static const String _keyBaseUrl = 'base_url';
  static const String _keyDeviceSn = 'device_sn';
  static const String _keyIsBound = 'is_bound';
  static const String _keyBoundOpdName = 'bound_opd_name';
  static const String _keyAntiSpoofingEnabled = 'anti_spoofing_enabled';

  // ── Default Values ──
  static const String defaultBaseUrl = 'http://192.168.100.57:5000';
  static const String defaultDeviceSn = 'WEB_APP_01';

  // ── Endpoint Constants ──
  static const String predictEndpoint = '/api/predict';
  static const String registerEndpoint = '/api/register/mobile';
  static const String bindEndpoint = '/api/devices/bind';
  static const String unlockEndpoint = '/api/predict/unlock';

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

  /// Returns whether the device has been bound to an OPD
  static Future<bool> getIsBound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsBound) ?? false;
  }

  /// Returns the name of the bound OPD (for display)
  static Future<String> getBoundOpdName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBoundOpdName) ?? '-';
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

  /// Saves the binding state
  static Future<void> setIsBound(bool bound) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsBound, bound);
  }

  /// Saves the bound OPD name
  static Future<void> setBoundOpdName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBoundOpdName, name);
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

  /// Returns the full bind API URL
  static Future<String> getBindUrl() async {
    final base = await getBaseUrl();
    return '$base$bindEndpoint';
  }

  /// Returns the full unlock API URL
  static Future<String> getUnlockUrl() async {
    final base = await getBaseUrl();
    return '$base$unlockEndpoint';
  }

  // ── Anti-Spoofing Config ──

  /// Returns whether anti-spoofing is enabled for this device.
  /// Defaults to true (secure by default) if never synced from server.
  static Future<bool> getAntiSpoofingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAntiSpoofingEnabled) ?? true;
  }

  /// Saves the anti-spoofing enabled state (synced from server heartbeat).
  static Future<void> setAntiSpoofingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAntiSpoofingEnabled, enabled);
  }
}
