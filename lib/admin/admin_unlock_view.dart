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
    final screenSize = MediaQuery.of(context).size;
    final circleSize = screenSize.width * 0.65;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview (full screen)
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Dark overlay with circular cutout
          Positioned.fill(
            child: ClipPath(
              clipper: _CircleCutoutClipper(circleSize),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withAlpha(180)),
              ),
            ),
          ),

          // Circle border
          Center(
            child: Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isProcessing
                      ? Colors.amber
                      : (_statusText.contains('❌')
                          ? Colors.red
                          : Colors.white.withAlpha(130)),
                  width: 3,
                ),
              ),
            ),
          ),

          // Animated scan line inside circle
          if (!_isProcessing)
            Center(
              child: AnimatedBuilder(
                animation: _scanLineController,
                builder: (context, _) {
                  final yOffset =
                      (_scanLineController.value - 0.5) * (circleSize - 20);
                  return Transform.translate(
                    offset: Offset(0, yOffset),
                    child: Container(
                      width: circleSize * 0.8,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.greenAccent.withAlpha(200),
                            Colors.greenAccent,
                            Colors.greenAccent.withAlpha(200),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withAlpha(80),
                            blurRadius: 12,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Verifikasi Admin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withAlpha(220)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status text
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _statusText.contains('❌')
                            ? Colors.red[300]
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Capture button
                  GestureDetector(
                    onTap: _isProcessing ? null : _captureAndVerify,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isProcessing
                            ? Colors.amber.withAlpha(60)
                            : Colors.white.withAlpha(30),
                      ),
                      child: _isProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(
                              Icons.fingerprint,
                              color: Colors.white,
                              size: 36,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isProcessing ? 'Memproses...' : 'Tap untuk verifikasi',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom clipper that cuts out a circle from the center
class _CircleCutoutClipper extends CustomClipper<Path> {
  final double diameter;
  _CircleCutoutClipper(this.diameter);

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circlePath = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: diameter,
        height: diameter,
      ));
    return Path.combine(PathOperation.difference, path, circlePath);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
