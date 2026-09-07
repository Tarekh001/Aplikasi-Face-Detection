import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// Service untuk Multi-Frame Anti-Spoofing via server-side temporal analysis.
///
/// Mengirim 3 foto berurutan (diambil ~200ms interval) ke server.
/// Server menganalisis PERUBAHAN antar frame untuk mendeteksi:
///   - Foto cetak (zero motion antar frame)
///   - Layar digital (screen flicker pattern)
///   - Wajah asli (micro-movement alami)
class AntiSpoofService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// Threshold — synced with backend FAS_THRESHOLD v3 (balanced)
  static const double livenessThreshold = 0.65;

  /// Jumlah frame yang harus diambil
  static const int requiredFrames = 3;

  /// Interval antar frame capture (milliseconds)
  static const int frameIntervalMs = 200;

  /// Check liveness dengan MULTI-FRAME.
  /// [imagePaths] harus berisi 3+ path file foto berurutan.
  static Future<LivenessResult?> checkLivenessMultiFrame(
      List<String> imagePaths) async {
    if (imagePaths.isEmpty) return null;

    try {
      final String baseUrl = await AppConfig.getBaseUrl();
      final String url = '$baseUrl/api/check-spoof';

      // Build multipart with frame_0, frame_1, frame_2, ...
      final Map<String, dynamic> formMap = {};
      for (int i = 0; i < imagePaths.length; i++) {
        formMap['frame_$i'] = await MultipartFile.fromFile(
          imagePaths[i],
          filename: 'frame_$i.jpg',
        );
      }

      final formData = FormData.fromMap(formMap);

      debugPrint(
          '[Anti-Spoof] Sending ${imagePaths.length} frames to server...');

      final response = await _dio.post(url, data: formData);

      if (response.statusCode == 200) {
        final data = response.data;
        final bool isReal = data['is_real'] ?? true;
        final double confidence =
            (data['confidence'] as num?)?.toDouble() ?? 0.0;
        final String label = data['label'] ?? 'UNKNOWN';
        final int framesAnalyzed = data['frames_analyzed'] ?? 0;

        debugPrint(
          '${isReal ? "🟢" : "🔴"} [Anti-Spoof] $label '
          '| Confidence: ${(confidence * 100).toStringAsFixed(1)}% '
          '| Frames: $framesAnalyzed',
        );

        return LivenessResult(
          score: confidence,
          isReal: isReal,
          faceDetected: label != 'NO_FACE',
          label: label,
        );
      } else {
        debugPrint('⚠️ [Anti-Spoof] Server ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      debugPrint('⚠️ [Anti-Spoof] Network: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ [Anti-Spoof] Error: $e');
      return null;
    }
  }

  /// Legacy single-frame check (backward compatible)
  static Future<LivenessResult?> checkLiveness(String imagePath) async {
    return checkLivenessMultiFrame([imagePath]);
  }
}

/// Result of anti-spoofing check.
class LivenessResult {
  final double score;
  final bool isReal;
  final bool faceDetected;
  final String label;

  const LivenessResult({
    required this.score,
    required this.isReal,
    required this.faceDetected,
    required this.label,
  });

  @override
  String toString() =>
      'LivenessResult(score: ${score.toStringAsFixed(3)}, isReal: $isReal, label: $label)';
}
