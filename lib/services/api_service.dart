import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import '../config/app_config.dart';
import '../models/predict_response.dart';
import '../models/api_error.dart';

/// Centralized API service for communicating with the Flask backend.
/// Handles predict (attendance) and register (enrollment) requests.

/// Thrown when backend returns DEVICE_NOT_FOUND or DeviceUnbound.
/// Device was deleted or unbound by admin — kiosk must re-activate.
class DeviceUnboundException implements Exception {
  final String message;
  DeviceUnboundException([this.message = 'Akses Kiosk diputus oleh Server. Silakan aktivasi ulang.']);
  @override
  String toString() => message;
}

/// Legacy alias — keep for backward compatibility
typedef DeviceNotFoundException = DeviceUnboundException;

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  /// Admin login via `POST /api/login`.
  ///
  /// Returns response map with `access_token` and `user` info.
  /// Throws [ApiError] on failure (401, 403, 404).
  static Future<Map<String, dynamic>> loginAdmin(
    String username,
    String password,
  ) async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final loginUrl = '$baseUrl/api/login';

      final response = await _dio.post(loginUrl, data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data;
      }
      throw ApiError.fromStatusCode(
        response.statusCode ?? 500,
        serverMessage: _extractErrorMessage(response.data),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        throw ApiError.fromStatusCode(
          e.response!.statusCode ?? 500,
          serverMessage: _extractErrorMessage(e.response?.data),
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      }
      throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Sends a face photo to `/api/predict` for attendance recognition.
  ///
  /// Reads `BASE_URL` and `DEVICE_SN` from SharedPreferences (AppConfig).
  /// Sends multipart/form-data with:
  ///   - `photo`: the cropped face image file
  ///   - `device_sn`: the device serial number configured by admin
  ///
  /// Returns [PredictResponse] on success (200).
  /// Throws [ApiError] on failure (400, 403, 500, network error).
  static Future<PredictResponse> predictFace(
    File photo, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final predictUrl = await AppConfig.getPredictUrl();
      final deviceSn = await AppConfig.getDeviceSn();

      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          photo.path,
          filename: basename(photo.path),
        ),
        'device_sn': deviceSn,
      });

      // Append GPS coordinates if available (geofencing support)
      if (latitude != null && longitude != null) {
        formData.fields.add(MapEntry('latitude_scan', latitude.toString()));
        formData.fields.add(MapEntry('longitude_scan', longitude.toString()));
      }

      final response = await _dio.post(predictUrl, data: formData);

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return PredictResponse.fromJson(response.data);
      } else {
        throw ApiError.fromStatusCode(
          response.statusCode ?? 500,
          serverMessage: _extractErrorMessage(response.data),
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        _checkDeviceNotFound(e.response?.data);
        throw ApiError.fromStatusCode(
          e.response!.statusCode ?? 500,
          serverMessage: _extractErrorMessage(e.response?.data),
        );
      }

      // Network-level errors
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw ApiError.fromException('Timeout: Server tidak merespon');
      } else if (e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      } else {
        throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
      }
    } on ApiError {
      rethrow;
    } on DeviceNotFoundException {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Registers a new employee via `/api/register/mobile`.
  ///
  /// Sends multipart/form-data with:
  ///   - `name`: employee full name
  ///   - `nip`: 18-digit NIP
  ///   - `device_sn`: kiosk serial number (OPD auto-detected by backend)
  ///   - `photos`: list of face photo files
  ///
  /// Returns the response data map on success.
  /// Throws [ApiError] on failure.
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String nip,
    required List<File> photos,
    String role = 'ASN',
  }) async {
    try {
      final registerUrl = await AppConfig.getRegisterUrl();
      final deviceSn = await AppConfig.getDeviceSn();

      final formData = FormData.fromMap({
        'name': name,
        'nip': nip,
        'device_sn': deviceSn,
        'role': role,
        'photos': [
          for (final photo in photos)
            await MultipartFile.fromFile(
              photo.path,
              filename: basename(photo.path),
            ),
        ],
      });

      final response = await _dio.post(registerUrl, data: formData);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data is Map<String, dynamic>) {
          return response.data;
        }
        return {'message': 'Registrasi berhasil'};
      } else {
        throw ApiError.fromStatusCode(
          response.statusCode ?? 500,
          serverMessage: _extractErrorMessage(response.data),
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw ApiError.fromStatusCode(
          e.response!.statusCode ?? 500,
          serverMessage: _extractErrorMessage(e.response?.data),
        );
      }

      if (e.type == DioExceptionType.connectionTimeout) {
        throw ApiError.fromException('Timeout: Server tidak merespon');
      } else if (e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      } else {
        throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Extracts error message from various response data formats.
  static String? _extractErrorMessage(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data['error']?.toString() ??
          data['message']?.toString() ??
          data.toString();
    }
    return data.toString();
  }

  /// Sends a background heartbeat to backend to auto-register IP, Platform, etc.
  /// Also syncs device-level config (anti_spoofing_enabled) from server.
  static Future<void> sendHeartbeat() async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final deviceSn = await AppConfig.getDeviceSn();
      final heartbeatUrl = '$baseUrl/api/devices/heartbeat';

      String platformName = 'Unknown';
      if (Platform.isAndroid) platformName = 'Android';
      else if (Platform.isIOS) platformName = 'iOS';
      else if (Platform.isWindows) platformName = 'Windows';

      String ipAddress = '';
      try {
        for (var interface in await NetworkInterface.list()) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              ipAddress = addr.address;
              break;
            }
          }
          if (ipAddress.isNotEmpty) break;
        }
      } catch (_) {}

      // NOTE: MAC Address / Device Model are hardcoded or require external plugins.
      // Doing best-effort sending here.
      final response = await _dio.post(heartbeatUrl, data: {
        'sn': deviceSn,
        'ip_address': ipAddress.isNotEmpty ? ipAddress : null,
        'platform': platformName,
        'device_name': 'Kiosk Mobile',
        // 'mac_address': 'xx:xx:xx:xx:xx' // Need network_info_plus for this
      });

      // ── Sync device config from server response ──
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['anti_spoofing_enabled'] != null) {
          final bool serverFlag = data['anti_spoofing_enabled'] as bool;
          await AppConfig.setAntiSpoofingEnabled(serverFlag);
          print('🛡️ [Heartbeat] anti_spoofing_enabled synced: $serverFlag');
        }
      }

      print('✅ [Heartbeat] Berhasil update data device ke server (SN: $deviceSn, IP: $ipAddress)');
    } catch (e) {
      print('⚠️ [Heartbeat] Gagal mengirim info: $e');
    }
  }

  /// Binds a device to the admin's OPD via `POST /api/devices/bind`.
  ///
  /// Requires a JWT token (from admin login).
  /// [token] - JWT access token from admin login.
  /// [deviceInfo] - Map containing device_sn, device_name, platform, etc.
  ///
  /// Returns response data map on success.
  /// Throws [ApiError] on failure.
  static Future<Map<String, dynamic>> bindDevice(
    String token,
    Map<String, dynamic> deviceInfo,
  ) async {
    try {
      final bindUrl = await AppConfig.getBindUrl();

      final response = await _dio.post(
        bindUrl,
        data: deviceInfo,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data;
      }
      throw ApiError.fromStatusCode(
        response.statusCode ?? 500,
        serverMessage: _extractErrorMessage(response.data),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        throw ApiError.fromStatusCode(
          e.response!.statusCode ?? 500,
          serverMessage: _extractErrorMessage(e.response?.data),
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      }
      throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Biometric admin unlock via `POST /api/predict/unlock`.
  ///
  /// Sends face photo + device_sn. Server checks if the face belongs
  /// to an admin authorized for this device's OPD.
  ///
  /// Returns response data map with `unlock`, `role`, `name`, etc.
  /// Throws [ApiError] on failure (403 = not admin, 401 = face not recognized).
  static Future<Map<String, dynamic>> adminUnlock(
    File photo,
    String deviceSn,
  ) async {
    try {
      final unlockUrl = await AppConfig.getUnlockUrl();

      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          photo.path,
          filename: basename(photo.path),
        ),
        'device_sn': deviceSn,
      });

      final response = await _dio.post(unlockUrl, data: formData);

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data;
      }
      throw ApiError.fromStatusCode(
        response.statusCode ?? 500,
        serverMessage: _extractErrorMessage(response.data),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        _checkDeviceNotFound(e.response?.data);
        throw ApiError.fromStatusCode(
          e.response!.statusCode ?? 500,
          serverMessage: _extractErrorMessage(e.response?.data),
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      }
      throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
    } on ApiError {
      rethrow;
    } on DeviceNotFoundException {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Checks if the server response contains device removal/unbind error codes.
  /// Throws [DeviceNotFoundException] if detected.
  // ═══════════════════════════════════════════════
  // KEGIATAN (Activity Attendance) APIs
  // ═══════════════════════════════════════════════

  /// Fetch active kegiatan for today — `GET /api/kegiatan/active`
  static Future<List<Map<String, dynamic>>> fetchActiveKegiatan() async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final response = await _dio.get('$baseUrl/api/kegiatan/active');
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Submit kegiatan attendance — `POST /api/predict/kegiatan`
  static Future<Map<String, dynamic>> predictKegiatan(
    File photo, {
    required int kegiatanId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final deviceSn = await AppConfig.getDeviceSn();

      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(photo.path, filename: basename(photo.path)),
        'device_sn': deviceSn,
        'kegiatan_id': kegiatanId.toString(),
      });

      if (latitude != null && longitude != null) {
        formData.fields.add(MapEntry('latitude_scan', latitude.toString()));
        formData.fields.add(MapEntry('longitude_scan', longitude.toString()));
      }

      final response = await _dio.post('$baseUrl/api/predict/kegiatan', data: formData);

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data;
      }
      throw ApiError.fromStatusCode(
        response.statusCode ?? 500,
        serverMessage: _extractErrorMessage(response.data),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        // Return error response data for UI handling
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          throw ApiError.fromStatusCode(
            e.response!.statusCode ?? 500,
            serverMessage: data['message']?.toString() ?? data['error']?.toString() ?? 'Gagal',
          );
        }
        throw ApiError.fromStatusCode(e.response!.statusCode ?? 500);
      }
      if (e.type == DioExceptionType.connectionError) {
        throw ApiError.fromException('Tidak dapat terhubung ke server');
      }
      throw ApiError.fromException('Kesalahan jaringan: ${e.message}');
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.fromException('Kesalahan: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────
  static void _checkDeviceNotFound(dynamic data) {
    if (data is Map) {
      final errorCode = data['error'];
      if (errorCode == 'DEVICE_NOT_FOUND' || errorCode == 'DeviceUnbound') {
        throw DeviceNotFoundException(
          data['message'] ?? 'Perangkat telah dihapus dari sistem. Silakan aktivasi ulang.',
        );
      }
    }
  }
}
