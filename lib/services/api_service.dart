import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import '../config/app_config.dart';
import '../models/predict_response.dart';
import '../models/api_error.dart';

/// Centralized API service for communicating with the Flask backend.
/// Handles predict (attendance) and register (enrollment) requests.
class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  /// Sends a face photo to `/api/predict` for attendance recognition.
  ///
  /// Reads `BASE_URL` and `DEVICE_SN` from SharedPreferences (AppConfig).
  /// Sends multipart/form-data with:
  ///   - `photo`: the cropped face image file
  ///   - `device_sn`: the device serial number configured by admin
  ///
  /// Returns [PredictResponse] on success (200).
  /// Throws [ApiError] on failure (400, 403, 500, network error).
  static Future<PredictResponse> predictFace(File photo) async {
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
    } catch (e) {
      throw ApiError.fromException('Kesalahan tidak terduga: $e');
    }
  }

  /// Registers a new employee via `/api/register`.
  ///
  /// Sends multipart/form-data with:
  ///   - `name`: employee full name
  ///   - `nip`: 18-digit NIP
  ///   - `opd_id`: the selected OPD/Instansi ID
  ///   - `source`: 'mobile' (triggers pending approval on backend)
  ///   - `photos`: list of face photo files
  ///
  /// Returns the response data map on success.
  /// Throws [ApiError] on failure.
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String nip,
    required int opdId,
    required List<File> photos,
  }) async {
    try {
      final registerUrl = await AppConfig.getRegisterUrl();
      final deviceSn = await AppConfig.getDeviceSn();

      final formData = FormData.fromMap({
        'name': name,
        'nip': nip,
        'opd_id': opdId,
        'source': 'mobile',
        'device_sn': deviceSn,
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

  /// Fetches the list of OPD/Instansi from `/api/opd/list` (public, no auth).
  /// Used by the registration form to populate the OPD dropdown.
  /// Returns a list of maps: [{ "id": 1, "nama": "Diskominfo", "kode": "OPD-001" }]
  static Future<List<Map<String, dynamic>>> fetchOpdList() async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final url = '$baseUrl/api/opd/list';

      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('⚠️ [OPD] Gagal mengambil daftar OPD: $e');
      return [];
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
      await _dio.post(heartbeatUrl, data: {
        'sn': deviceSn,
        'ip_address': ipAddress.isNotEmpty ? ipAddress : null,
        'platform': platformName,
        'device_name': 'Kiosk Mobile',
        // 'mac_address': 'xx:xx:xx:xx:xx' // Need network_info_plus for this
      });
      print('✅ [Heartbeat] Berhasil update data device ke server (SN: $deviceSn, IP: $ipAddress)');
    } catch (e) {
      print('⚠️ [Heartbeat] Gagal mengirim info: $e');
    }
  }
}
