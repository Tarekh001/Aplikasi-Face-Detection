import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/api_error.dart';
import 'admin_menu_view.dart';

/// Biometric Admin Unlock — Separate view with its own camera.
///
/// Flow:
///   1. Opens front camera in a circular cutout
///   2. Animated scanning line sweeps vertically
///   3. Auto-captures after 2 seconds (or user taps "Verifikasi")
///   4. Sends photo to /api/predict/unlock
///   5. Success → pushReplacement to AdminMenuView
///   6. Fail → pop back to PresensiView
class AdminUnlockView extends StatefulWidget {
  const AdminUnlockView({super.key});

  @override
  State<AdminUnlockView> createState() => _AdminUnlockViewState();
}

class _AdminUnlockViewState extends State<AdminUnlockView>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isProcessing = false;
  String _statusText = 'Posisikan wajah Admin...';
  late AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _statusText = 'Kamera tidak tersedia');
        return;
      }

      final frontCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras[0],
      );

      _cameraController = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('⚠️ AdminUnlock camera error: $e');
      setState(() => _statusText = 'Gagal membuka kamera');
    }
  }

  Future<void> _captureAndVerify() async {
    if (_isProcessing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Memverifikasi wajah Admin...';
    });

    try {
      final XFile xFile = await _cameraController!.takePicture();
      final deviceSn = await AppConfig.getDeviceSn();

      final result = await ApiService.adminUnlock(File(xFile.path), deviceSn);

      if (!mounted) return;

      if (result['unlock'] == true) {
        final role = result['role'] ?? 'admin';
        final name = result['name'] ?? 'Admin';

        // Dispose camera before navigating
        await _disposeCamera();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminMenuView(adminName: name, role: role),
          ),
        );
      } else {
        setState(() {
          _statusText = 'Verifikasi gagal. Coba lagi.';
          _isProcessing = false;
        });
      }
    } on DeviceUnboundException catch (e) {
      // Device deleted/unbound — force logout
      await AppConfig.setIsBound(false);
      await AppConfig.setDeviceSn('');
      await AppConfig.setBoundOpdName('');

      if (!mounted) return;
      await _disposeCamera();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } on ApiError catch (e) {
      if (!mounted) return;

      String errorMsg = e.error;
      if (e.error.contains('Akses khusus Admin') || e.error.contains('role')) {
        errorMsg = 'Hanya Admin yang dapat mengakses menu ini.';
      } else if (e.error.contains('Bukan Admin instansi') || e.error.contains('bukan Admin')) {
        errorMsg = 'Anda bukan Admin instansi ini.';
      } else if (e.error.contains('tidak dikenali')) {
        errorMsg = 'Wajah tidak dikenali.';
      }

      setState(() {
        _statusText = '❌ $errorMsg';
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Error: ${e.toString().split('\n').first}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.dispose();
      }
    } catch (_) {}
    _cameraController = null;
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E293B), // Slate 800
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ═══════════════════════════════════════════════════
              // 1. HEADER (flex: 15) — Title & Back Navigation
              // ═══════════════════════════════════════════════════
              Expanded(
                flex: 15,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Autentikasi Admin',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Verifikasi Biometrik Wajah Administrator',
                              style: TextStyle(
                                color: const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ═══════════════════════════════════════════════════
              // 2. BODY (flex: 60) — Undistorted Circular Camera
              // ═══════════════════════════════════════════════════
              Expanded(
                flex: 60,
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Dynamically calculate circular diameter based on available space
                      final maxDim = constraints.biggest.shortestSide;
                      final circleDiameter = (maxDim * 0.85).clamp(200.0, 360.0);

                      return Container(
                        width: circleDiameter,
                        height: circleDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _isProcessing
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                                  : (_statusText.contains('❌')
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                                      : const Color(0xFF2563EB).withValues(alpha: 0.3)),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Undistorted Camera Feed
                            ClipOval(
                              child: Container(
                                width: circleDiameter,
                                height: circleDiameter,
                                color: const Color(0xFF1E293B),
                                child: (_cameraController != null &&
                                        _cameraController!.value.isInitialized)
                                    ? LayoutBuilder(
                                        builder: (context, cameraConstraints) {
                                          final camVal = _cameraController!.value;
                                          // Camera aspect ratio in portrait orientation
                                          final previewRatio = camVal.isInitialized
                                              ? 1.0 / camVal.aspectRatio
                                              : 1.0;
                                          return OverflowBox(
                                            alignment: Alignment.center,
                                            child: FittedBox(
                                              fit: BoxFit.cover,
                                              child: SizedBox(
                                                width: circleDiameter,
                                                height: circleDiameter / previewRatio,
                                                child: CameraPreview(_cameraController!),
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : const Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF2563EB),
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                              ),
                            ),

                            // Animated Scanning Line inside Circle
                            if (!_isProcessing &&
                                _cameraController != null &&
                                _cameraController!.value.isInitialized)
                              ClipOval(
                                child: SizedBox(
                                  width: circleDiameter,
                                  height: circleDiameter,
                                  child: AnimatedBuilder(
                                    animation: _scanLineController,
                                    builder: (context, _) {
                                      final yOffset = (_scanLineController.value - 0.5) *
                                          (circleDiameter - 20);
                                      return Transform.translate(
                                        offset: Offset(0, yOffset),
                                        child: Container(
                                          width: circleDiameter,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                const Color(0xFF38BDF8)
                                                    .withValues(alpha: 0.8),
                                                const Color(0xFF38BDF8),
                                                const Color(0xFF38BDF8)
                                                    .withValues(alpha: 0.8),
                                                Colors.transparent,
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF38BDF8)
                                                    .withValues(alpha: 0.6),
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                            // Circular Glowing Border Ring
                            IgnorePointer(
                              child: Container(
                                width: circleDiameter,
                                height: circleDiameter,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isProcessing
                                        ? const Color(0xFFF59E0B)
                                        : (_statusText.contains('❌')
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF60A5FA)
                                                .withValues(alpha: 0.8)),
                                    width: 3.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ═══════════════════════════════════════════════════
              // 3. FOOTER (flex: 25) — Status & Fingerprint Button
              // ═══════════════════════════════════════════════════
              Expanded(
                flex: 25,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: _statusText.contains('❌')
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : (_isProcessing
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _statusText.contains('❌')
                                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                : (_isProcessing
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                    : Colors.white.withValues(alpha: 0.15)),
                          ),
                        ),
                        child: Text(
                          _statusText,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _statusText.contains('❌')
                                ? const Color(0xFFFCA5A5)
                                : (_isProcessing
                                    ? const Color(0xFFFDE68A)
                                    : Colors.white),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Fingerprint Verification Action Button
                      GestureDetector(
                        onTap: _isProcessing ? null : _captureAndVerify,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isProcessing
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                                : const Color(0xFF2563EB),
                            border: Border.all(
                              color: _isProcessing
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF93C5FD),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isProcessing
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF2563EB))
                                    .withValues(alpha: 0.4),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _isProcessing
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.8,
                                    color: Color(0xFFF59E0B),
                                  ),
                                )
                              : const Icon(
                                  Icons.fingerprint_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isProcessing ? 'Memverifikasi...' : 'Ketuk untuk Verifikasi',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
