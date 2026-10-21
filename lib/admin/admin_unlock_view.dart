import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/api_error.dart';
import 'admin_menu_view.dart';

/// Biometric Admin Unlock — Modern Soft-UI Kiosk View (Portrait & Landscape Ready).
///
/// Features:
///   1. Undistorted 3:4 rounded rectangular camera card (matching PresensiView)
///   2. Responsive layout: Single-column in Portrait (Phone), Two-column in Landscape (Tablet)
///   3. Full camera controls: Switch Front/Back Camera, Rotate 90°, Refresh Camera
///   4. Upright image baking (_ensureImageUpright) before sending to /api/predict/unlock
class AdminUnlockView extends StatefulWidget {
  const AdminUnlockView({super.key});

  @override
  State<AdminUnlockView> createState() => _AdminUnlockViewState();
}

class _AdminUnlockViewState extends State<AdminUnlockView> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  int _manualRotationQuarterTurns = 0;

  String _statusText = 'Posisikan wajah Admin di dalam area oval';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera({CameraLensDirection? preferredLens}) async {
    if (_isSwitchingCamera) return;
    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      await _disposeCamera();

      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _statusText = 'Kamera tidak tersedia';
            _isSwitchingCamera = false;
          });
        }
        return;
      }

      final targetLens = preferredLens ?? _currentLensDirection;
      final selectedCam = _cameras.firstWhere(
        (c) => c.lensDirection == targetLens,
        orElse: () => _cameras.first,
      );
      _currentLensDirection = selectedCam.lensDirection;

      final controller = CameraController(
        selectedCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isSwitchingCamera = false;
        _statusText = 'Posisikan wajah Admin di dalam area oval';
      });
    } catch (e) {
      debugPrint('⚠️ AdminUnlock camera error: $e');
      if (mounted) {
        setState(() {
          _statusText = 'Gagal membuka kamera';
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _switchCameraLens() async {
    if (_isProcessing || _isSwitchingCamera || _cameras.length < 2) return;
    final nextLens = _currentLensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    setState(() {
      _manualRotationQuarterTurns = 0;
      _statusText = nextLens == CameraLensDirection.front
          ? 'Beralih ke Kamera Depan...'
          : 'Beralih ke Kamera Belakang...';
    });

    await _initCamera(preferredLens: nextLens);
  }

  void _toggleCameraRotation() {
    if (_isProcessing || _isSwitchingCamera) return;
    setState(() {
      _manualRotationQuarterTurns = (_manualRotationQuarterTurns + 1) % 4;
      _statusText =
          'Orientasi kamera diputar (${_manualRotationQuarterTurns * 90}°)';
    });
  }

  Future<void> _refreshCamera() async {
    if (_isProcessing || _isSwitchingCamera) return;
    setState(() {
      _statusText = 'Memuat ulang kamera...';
    });
    await _initCamera(preferredLens: _currentLensDirection);
  }

  int _getDisplayRotationQuarterTurns() {
    final camera = _cameraController?.description;
    if (camera == null) return _manualRotationQuarterTurns;

    final isTabletLandscapeSensor = camera.sensorOrientation == 0;
    final isPortraitDisplay =
        MediaQuery.of(context).size.height >= MediaQuery.of(context).size.width;

    int autoTurns = 0;
    if (isTabletLandscapeSensor && isPortraitDisplay) {
      autoTurns = 1;
    }

    return (autoTurns + _manualRotationQuarterTurns) % 4;
  }

  /// Memastikan orientasi file foto tegak lurus (upright) sesuai tampilan di layar.
  Future<String> _ensureImageUpright(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return imagePath;

      // 1. Bake EXIF orientation ke raw pixels
      decoded = img.bakeOrientation(decoded);

      // 2. Terapkan rotasi kompensasi jika pengguna memutar kamera secara manual
      if (_manualRotationQuarterTurns != 0) {
        decoded = img.copyRotate(
          decoded,
          angle: _manualRotationQuarterTurns * 90,
        );
      }

      final rotatedBytes = img.encodeJpg(decoded, quality: 95);
      await file.writeAsBytes(rotatedBytes);
      return imagePath;
    } catch (e) {
      debugPrint('⚠️ [AdminUnlock] Gagal memproses rotasi gambar: $e');
      return imagePath;
    }
  }

  Future<void> _captureAndVerify() async {
    if (_isProcessing || _isSwitchingCamera) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = 'Memverifikasi wajah Admin...';
    });

    try {
      final XFile xFile = await _cameraController!.takePicture();
      final String uprightPath = await _ensureImageUpright(xFile.path);
      final deviceSn = await AppConfig.getDeviceSn();

      final result = await ApiService.adminUnlock(File(uprightPath), deviceSn);

      // Bersihkan file sementara
      try {
        await File(uprightPath).delete();
      } catch (_) {}

      if (!mounted) return;

      if (result['unlock'] == true) {
        final role = result['role'] ?? 'admin';
        final name = result['name'] ?? 'Admin';

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
          _statusText = '❌ Verifikasi gagal. Coba lagi.';
          _isProcessing = false;
        });
      }
    } on DeviceUnboundException catch (e) {
      await AppConfig.setIsBound(false);
      await AppConfig.setDeviceSn('');
      await AppConfig.setBoundOpdName('');

      if (!mounted) return;
      await _disposeCamera();

      if (!mounted) return;
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
      } else if (e.error.contains('Bukan Admin instansi') ||
          e.error.contains('bukan Admin')) {
        errorMsg = 'Anda bukan Admin instansi ini.';
      } else if (e.error.contains('tidak dikenali')) {
        errorMsg = 'Wajah Admin tidak dikenali.';
      }

      setState(() {
        _statusText = '❌ $errorMsg';
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = '❌ Error: ${e.toString().split('\n').first}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        if (controller.value.isInitialized) {
          await controller.dispose();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposeCamera();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CAMERA PREVIEW (100% Undistorted & Rotation-Aware)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCameraFeed() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const SizedBox();
    }

    final int quarterTurns = _getDisplayRotationQuarterTurns();
    final double rawAr = _cameraController!.value.aspectRatio;
    final bool isScreenLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final double cameraPreviewRatio =
        isScreenLandscape ? rawAr : (1.0 / rawAr);

    return ClipRect(
      child: Center(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: SizedBox(
                width: 1000.0,
                height: 1000.0 / cameraPreviewRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraCard(double shortSide) {
    final bool hasError = _statusText.contains('❌');
    final Color activeBorderColor = _isProcessing
        ? const Color(0xFFF59E0B)
        : (hasError
            ? const Color(0xFFEF4444)
            : const Color(0xFF3B82F6).withValues(alpha: 0.45));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: activeBorderColor,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: activeBorderColor.withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: (_cameraController == null ||
                !_cameraController!.value.isInitialized ||
                _isSwitchingCamera)
            ? Container(
                color: const Color(0xFF1E293B),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF60A5FA),
                        strokeWidth: 2.5,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _isSwitchingCamera
                            ? 'Mengalihkan kamera...'
                            : 'Menyiapkan kamera autentikasi...',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, cardConstraints) {
                  final cardW = cardConstraints.maxWidth;
                  final cardH = cardConstraints.maxHeight;
                  final double localOvalW = (cardW * 0.62).clamp(150.0, 340.0);
                  final double localOvalH =
                      (localOvalW * 1.32).clamp(190.0, cardH * 0.78);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Undistorted Camera Feed
                      _buildCameraFeed(),

                      // 2. Dark Vignette Overlay with Oval Cutout
                      CustomPaint(
                        painter: _AdminOvalMaskPainter(
                          ovalWidth: localOvalW,
                          ovalHeight: localOvalH,
                          borderColor: _isProcessing
                              ? const Color(0xFFF59E0B)
                              : (hasError
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF60A5FA)),
                        ),
                      ),

                      // 3. Active Camera Badge (Top Center inside Card)
                      Positioned(
                        top: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0F172A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _currentLensDirection ==
                                          CameraLensDirection.front
                                      ? Icons.camera_front_rounded
                                      : Icons.camera_rear_rounded,
                                  color: const Color(0xFF60A5FA),
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _currentLensDirection ==
                                          CameraLensDirection.front
                                      ? 'Kamera Depan'
                                      : 'Kamera Belakang',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_manualRotationQuarterTurns != 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2563EB)
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_manualRotationQuarterTurns * 90}°',
                                      style: const TextStyle(
                                        color: Color(0xFF93C5FD),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTopActionButtons(double iconSize) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_cameras.length > 1) ...[
          _circleActionButton(
            icon: Icons.cameraswitch_rounded,
            tooltip: 'Ganti Kamera Depan/Belakang',
            onTap: _switchCameraLens,
            iconSize: iconSize,
          ),
          const SizedBox(width: 8),
        ],
        _circleActionButton(
          icon: Icons.rotate_90_degrees_cw_rounded,
          tooltip: 'Putar Orientasi Kamera 90°',
          onTap: _toggleCameraRotation,
          iconSize: iconSize,
        ),
        const SizedBox(width: 8),
        _circleActionButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Muat Ulang Kamera',
          onTap: _refreshCamera,
          iconSize: iconSize,
        ),
      ],
    );
  }

  Widget _circleActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double iconSize,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.92),
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCapsule() {
    final bool hasError = _statusText.contains('❌');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: hasError
            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
            : (_isProcessing
                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                : const Color(0xFF1E293B).withValues(alpha: 0.9)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError
              ? const Color(0xFFEF4444).withValues(alpha: 0.45)
              : (_isProcessing
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasError
                ? Icons.error_outline_rounded
                : (_isProcessing
                    ? Icons.hourglass_top_rounded
                    : Icons.admin_panel_settings_rounded),
            color: hasError
                ? const Color(0xFFFCA5A5)
                : (_isProcessing
                    ? const Color(0xFFFDE68A)
                    : const Color(0xFF60A5FA)),
            size: 20,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _statusText,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasError
                    ? const Color(0xFFFCA5A5)
                    : (_isProcessing
                        ? const Color(0xFFFDE68A)
                        : Colors.white),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: (_isProcessing || _isSwitchingCamera)
              ? null
              : _captureAndVerify,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isProcessing
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                  : const Color(0xFF2563EB),
              border: Border.all(
                color: _isProcessing
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF93C5FD),
                width: 3.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isProcessing
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF2563EB))
                      .withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      color: Color(0xFFF59E0B),
                    ),
                  )
                : const Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isProcessing ? 'Memverifikasi...' : 'Ketuk untuk Verifikasi Admin',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final bool isLandscape = mq.width > mq.height;
    final double shortSide = mq.shortestSide;
    final double padH = (shortSide * 0.04).clamp(14.0, 28.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
            ],
          ),
        ),
        child: SafeArea(
          child: isLandscape
              ? _buildLandscapeBody(padH, shortSide)
              : _buildPortraitBody(mq, padH, shortSide),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PORTRAIT LAYOUT (Smartphone & Portrait Tablet)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPortraitBody(Size mq, double padH, double shortSide) {
    final double maxCardH = mq.height * 0.54;
    final double cardW =
        (maxCardH * (3 / 4)).clamp(220.0, mq.width - (padH * 2));
    final double cardH = cardW * (4 / 3);

    return Column(
      children: [
        // 1. Top Header Bar
        Padding(
          padding: EdgeInsets.fromLTRB(padH * 0.7, 10, padH * 0.7, 8),
          child: Row(
            children: [
              _circleActionButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Kembali',
                onTap: () => Navigator.pop(context),
                iconSize: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Autentikasi Admin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Verifikasi Wajah Administrator',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _buildTopActionButtons(19),
            ],
          ),
        ),

        // 2. Proportional 3:4 Camera Card
        Expanded(
          child: Center(
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: _buildCameraCard(shortSide),
            ),
          ),
        ),

        // 3. Footer Controls (Status + Fingerprint Verify Button)
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 10, padH, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusCapsule(),
              const SizedBox(height: 14),
              _buildVerifyButton(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LANDSCAPE LAYOUT (Tablet / Kiosk Landscape)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildLandscapeBody(double padH, double shortSide) {
    return Column(
      children: [
        // 1. Dedicated Top Bar
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: padH,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              _circleActionButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Kembali',
                onTap: () => Navigator.pop(context),
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Autentikasi Admin Kiosk',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Gunakan tombol putar kamera di kanan atas jika orientasi kamera perlu disesuaikan',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildTopActionButtons(20),
            ],
          ),
        ),

        // 2. Two-Column Body: Camera Left, Controls Right
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: padH,
              vertical: padH * 0.5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Column: 3:4 Camera Card
                Expanded(
                  flex: 5,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: _buildCameraCard(shortSide),
                    ),
                  ),
                ),
                SizedBox(width: padH),

                // Right Column: Instructions + Status + Verify Button
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.verified_user_rounded,
                                    color: Color(0xFF60A5FA),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Verifikasi Biometrik Administrator',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Hanya Admin OPD yang terdaftar pada instansi perangkat ini atau Super Admin yang dapat membuka menu pengaturan & registrasi.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildStatusCapsule(),
                          const SizedBox(height: 22),
                          _buildVerifyButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom Painter for Dark Vignette with Oval Face Cutout & Corner Markers
class _AdminOvalMaskPainter extends CustomPainter {
  final double ovalWidth;
  final double ovalHeight;
  final Color borderColor;

  _AdminOvalMaskPainter({
    required this.ovalWidth,
    required this.ovalHeight,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.48);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    final overlayPaint = Paint()..color = const Color(0x73000000);
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, overlayPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..color = borderColor;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _AdminOvalMaskPainter old) =>
      old.ovalWidth != ovalWidth ||
      old.ovalHeight != ovalHeight ||
      old.borderColor != borderColor;
}
