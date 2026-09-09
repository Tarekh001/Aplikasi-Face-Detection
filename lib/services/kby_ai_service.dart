import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:facesdk_plugin/facesdk_plugin.dart';

/// Singleton service for KBY-AI Face Anti-Spoofing SDK.
///
/// Handles SDK initialization (activation + init + param config) and provides
/// a simple `checkLiveness(imagePath)` method that returns a liveness score.
///
/// Usage:
///   await KbyAiService.init();                           // Call once at startup
///   final result = await KbyAiService.checkLiveness(path); // Per-frame check
class KbyAiService {
  static final FacesdkPlugin _sdk = FacesdkPlugin();
  static bool _isInitialized = false;
  static bool _initFailed = false;

  /// Default liveness threshold — faces below this score are considered SPOOF.
  static const double livenessThreshold = 0.7;

  // ══════════════════════════════════════════════
  //  LICENSE KEYS — Replace with your own keys!
  // ══════════════════════════════════════════════
  // These are the demo/trial keys from the KBY-AI sample app.
  // They work for development & testing. For production, obtain
  // your own license from https://kby-ai.com
  static const String _androidLicenseKey =
      "PjnUMBHfBhtT/oa8ySF6mwinqAj2oBls4vSsDmsdrpL/xHwPLtq9Dll/4IIe2KIkXQEh81/21yQhK"
      "AUQOmCvuuNcaZX+DS/EBhinprH+Y+XBzdGz2KWKEZjeDnhoSo8ql1CDDmMiCdRleZ7PbcPv10/dkdI"
      "mwGLFerErQxL/qKIz+8CQqOryw/7RjpNgkbpufY+Nd635HN3dbG4Z+AKdpsl2hB+hl/16O1IhQiGia"
      "4V2+1q9PsFfj6HFST+CQD17kXfsXkoQzMsFwQn4BSuyiiPUdHfJ+EFYMoeF96Jhqfe1CH3af41l0wK"
      "LNqXthBE24m96v06lDFPXkxDOCZCzug==";

  static const String _iosLicenseKey =
      "LvqLS/kUqek3yNzQYaskd7H2oQZeZ/9msTJ16au/DAz0ZcDtnJUqlY6Du5YffkGKZ2oWlCrE8JBJfb"
      "rVcPvchPnZv6ZDOSZ9R1JCg+KlmyCQ2s6Xre6nhcjoAjvKbVhY3wFpwWOeKuvsCzv6hmKf5YBUMa6I"
      "yTwcqsoCKbcVq5mJDWbWpQXwKOiFXwhmyXHBruWzI1Jd6i6cNzYRixgqLWi1sS3Kak5EiHhc91TKPd"
      "LmZkLQQwWxr2OFSS8s3MRhrooAxxRU7XVglU+cg7tpqjvMcUSfbcLE8OYCV8DDIZfbBpEp5y1YN/gg"
      "OpX04tojhkSIhX9l5MRTiZfMdovaZg==";

  /// Whether the SDK was initialized successfully.
  static bool get isReady => _isInitialized && !_initFailed;

  /// Initialize the KBY-AI SDK. Call once at app startup (main.dart).
  /// Returns true if activation + init succeeded.
  static Future<bool> init() async {
    if (_isInitialized) return !_initFailed;

    try {
      // Step 1: Activate license
      final String licenseKey =
          Platform.isAndroid ? _androidLicenseKey : _iosLicenseKey;

      final int activationResult =
          await _sdk.setActivation(licenseKey) ?? -1;

      if (activationResult != 0) {
        debugPrint('❌ [KBY-AI] Activation FAILED: code=$activationResult');
        debugPrint('   ↳ -1=Invalid, -2=Expired, -3=Invalid, -4=Not activated');
        _isInitialized = true;
        _initFailed = true;
        return false;
      }

      debugPrint('✅ [KBY-AI] License activated successfully');

      // Step 2: Initialize the engine
      final int initResult = await _sdk.init() ?? -1;
      if (initResult != 0) {
        debugPrint('❌ [KBY-AI] Engine init FAILED: code=$initResult');
        _isInitialized = true;
        _initFailed = true;
        return false;
      }

      debugPrint('✅ [KBY-AI] Engine initialized');

      // Step 3: Set liveness detection level
      // 0 = Best Accuracy, 1 = Light Weight
      await _sdk.setParam({'check_liveness_level': 0});
      debugPrint('✅ [KBY-AI] Liveness level set to: Best Accuracy');

      _isInitialized = true;
      _initFailed = false;
      return true;
    } catch (e) {
      debugPrint('❌ [KBY-AI] Init exception: $e');
      _isInitialized = true;
      _initFailed = true;
      return false;
    }
  }

  /// Run passive liveness detection on a captured image file.
  ///
  /// Returns a [LivenessResult] containing:
  ///   - `score`: liveness confidence (0.0 - 1.0)
  ///   - `isReal`: true if score >= [livenessThreshold]
  ///   - `faceDetected`: true if at least one face was found
  ///
  /// Returns null if the SDK is not initialized or an error occurs.
  static Future<LivenessResult?> checkLiveness(String imagePath) async {
    if (!isReady) {
      debugPrint('⚠️ [KBY-AI] SDK not ready, skipping liveness check');
      return null;
    }

    try {
      final faces = await _sdk.extractFaces(imagePath);

      if (faces == null || faces.isEmpty) {
        return LivenessResult(
          score: 0.0,
          isReal: false,
          faceDetected: false,
        );
      }

      // Use the first (largest/most confident) face
      final face = faces[0];
      final double livenessScore = (face['liveness'] as num?)?.toDouble() ?? 0.0;

      final bool isReal = livenessScore >= livenessThreshold;

      debugPrint(
        '${isReal ? "🟢" : "🔴"} [KBY-AI] Liveness: ${(livenessScore * 100).toStringAsFixed(1)}% '
        '| ${isReal ? "REAL" : "SPOOF"} '
        '| Threshold: ${(livenessThreshold * 100).toStringAsFixed(0)}%',
      );

      return LivenessResult(
        score: livenessScore,
        isReal: isReal,
        faceDetected: true,
      );
    } catch (e) {
      debugPrint('❌ [KBY-AI] checkLiveness error: $e');
      return null;
    }
  }
}

/// Result of a KBY-AI passive liveness check.
class LivenessResult {
  /// Liveness confidence score (0.0 = definitely fake, 1.0 = definitely real).
  final double score;

  /// Whether the face is considered real (score >= threshold).
  final bool isReal;

  /// Whether a face was detected in the image at all.
  final bool faceDetected;

  const LivenessResult({
    required this.score,
    required this.isReal,
    required this.faceDetected,
  });

  @override
  String toString() =>
      'LivenessResult(score: ${score.toStringAsFixed(3)}, isReal: $isReal, faceDetected: $faceDetected)';
}
