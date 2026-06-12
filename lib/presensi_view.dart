import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

import 'config/app_config.dart';
import 'services/api_service.dart';
import 'services/anti_spoof_service.dart';
import 'models/api_error.dart';
import 'hasil_view.dart';
import 'admin/admin_unlock_view.dart';
import 'settings/settings_view.dart';

// ═══════════════════════════════════════════════════════════════
// STATE MACHINE — 4-Phase Liveness Pipeline
// ═══════════════════════════════════════════════════════════════
// Phase 0: FACE_DETECTION  → ML Kit gatekeeper (idle until face found)
// Phase 1: PASSIVE_CHECK   → Server-side MiniFASNet anti-spoofing
// Phase 2: ACTIVE_LIVENESS → ML Kit (blink + head turn)
// Phase 3: COUNTDOWN       → 3-2-1 → Capture → Upload
// ═══════════════════════════════════════════════════════════════
enum PresensiPhase {
  faceDetection,
  passiveCheck,
  activeLiveness,
  countdown,
  uploading,
  error,
}

class PresensiView extends StatefulWidget {
  const PresensiView({super.key});

  @override
  State<PresensiView> createState() => _PresensiViewState();
}

class _PresensiViewState extends State<PresensiView>
    with TickerProviderStateMixin {
  // ── Camera ──
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;

  // ── State Machine ──
  PresensiPhase _phase = PresensiPhase.faceDetection;

  // ── Phase 0: Face Detection Gatekeeper ──
  bool _isFaceDetected = false;
  bool _isGatekeeperProcessing = false;
  bool _antiSpoofEnabled = true;  // cached from AppConfig

  // ── Phase 1: Passive Anti-Spoofing (Server-side) ──
  Timer? _passiveCheckTimer;
  bool _isPassiveChecking = false;
  double _livenessScore = 0.0;
  int _consecutiveRealCount = 0;
  static const int _requiredConsecutiveReal = 3;

  // ── Phase 2: Active Liveness (ML Kit) ──
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  bool _isDetecting = false;
  bool _hasBlinked = false;
  bool _hasTurnedHead = false;

  // ── Phase 3: Countdown ──
  int _countdownValue = 3;

  // ── UI States ──
  String _statusText = "Menganalisis tekstur wajah...";
  String _errorMessage = '';
  Timer? _errorResetTimer;

  // ── Animations ──
  late AnimationController _pulseController;

  // ── OPD Name (for display + 7-tap hatch) ──
  String _opdName = 'Memuat...';

  // ── Emergency Hatch (7 rapid taps → PIN dialog) ──
  int _emergencyTapCount = 0;
  DateTime _lastTapTime = DateTime(2000);

  // ── Inactivity Timeout ──
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _resetIdleTimer();
    _loadOpdName();
    _initializeCamera();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _passiveCheckTimer?.cancel();
    _errorResetTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _loadOpdName() async {
    final name = await AppConfig.getBoundOpdName();
    if (mounted) setState(() => _opdName = name);
  }

  // ═══════════════════════════════════════════
  // CAMERA INITIALIZATION
  // ═══════════════════════════════════════════
  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception("Tidak ada kamera");

      final camera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras[0],
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // ── Cache the anti-spoofing config once ──
      _antiSpoofEnabled = await AppConfig.getAntiSpoofingEnabled();
      debugPrint('🛡️ [Config] anti_spoofing_enabled = $_antiSpoofEnabled');

      setState(() {});

      // ── Start Phase 0: Face Detection Gatekeeper ──
      _startFaceGatekeeper();
    } catch (e) {
      debugPrint("⚠️ Error _initializeCamera: $e");
      setState(() => _statusText = "Kamera tidak dapat diinisialisasi ❌");
    }
  }

  // ═══════════════════════════════════════════
  // PHASE 0: FACE DETECTION GATEKEEPER
  // ═══════════════════════════════════════════
  void _startFaceGatekeeper() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() {
      _phase = PresensiPhase.faceDetection;
      _isFaceDetected = false;
      _statusText = "Arahkan wajah ke kamera 📷";
    });

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isGatekeeperProcessing || _phase != PresensiPhase.faceDetection) return;
      _isGatekeeperProcessing = true;

      try {
        final faces = await _detectFaces(image);
        if (!mounted || _phase != PresensiPhase.faceDetection) return;

        if (faces.isNotEmpty) {
          // Face found → stop the stream and advance
          debugPrint('👤 [Gatekeeper] Face detected! Advancing...');
          await _cameraController!.stopImageStream();
          if (!mounted) return;
          setState(() => _isFaceDetected = true);
          _onFaceGatekeeperTriggered();
        } else {
          // No face — keep scanning
          if (mounted && _phase == PresensiPhase.faceDetection) {
            setState(() {
              _isFaceDetected = false;
              _statusText = "Arahkan wajah ke kamera 📷";
            });
          }
        }
      } catch (e) {
        debugPrint('⚠️ [Gatekeeper] Error: $e');
      }
      _isGatekeeperProcessing = false;
    });
  }

  /// Called once a face is detected by the gatekeeper.
  /// Routes to the correct phase based on anti-spoofing config.
  void _onFaceGatekeeperTriggered() {
    if (!_antiSpoofEnabled) {
      debugPrint('🛡️ [Gatekeeper] Anti-spoofing OFF → skip to countdown');
      _startCountdown();
    } else {
      debugPrint('🛡️ [Gatekeeper] Anti-spoofing ON → start passive check');
      _startPassiveCheck();
    }
  }

  // ═══════════════════════════════════════════
  // PHASE 1: SERVER-SIDE ANTI-SPOOFING
  // ═══════════════════════════════════════════
  void _startPassiveCheck() {
    setState(() {
      _phase = PresensiPhase.passiveCheck;
      _statusText = "🛡️ Menganalisis gerakan wajah...";
      _livenessScore = 0.0;
      _consecutiveRealCount = 0;
    });

    _passiveCheckTimer?.cancel();
    // Interval lebih panjang karena capture 3 frame + upload + analisis
    _passiveCheckTimer = Timer.periodic(
      const Duration(milliseconds: 3000),
      (_) => _runPassiveCheck(),
    );
    // Run immediately on first call
    _runPassiveCheck();
  }

  Future<void> _runPassiveCheck() async {
    if (_isPassiveChecking ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _phase != PresensiPhase.passiveCheck) {
      return;
    }
    _isPassiveChecking = true;

    List<String> framePaths = [];

    try {
      setState(() => _statusText = "🛡️ Mengambil frame...");

      // Capture 3 frames with 200ms interval
      for (int i = 0; i < AntiSpoofService.requiredFrames; i++) {
        if (!mounted || _phase != PresensiPhase.passiveCheck) break;
        final XFile xFile = await _cameraController!.takePicture();
        framePaths.add(xFile.path);
        if (i < AntiSpoofService.requiredFrames - 1) {
          await Future.delayed(
            Duration(milliseconds: AntiSpoofService.frameIntervalMs),
          );
        }
      }

      if (framePaths.length < 2) {
        _isPassiveChecking = false;
        return;
      }

      setState(() => _statusText = "🛡️ Menganalisis gerakan wajah...");

      // Send all frames to server for multi-frame temporal analysis
      final LivenessResult? result =
          await AntiSpoofService.checkLivenessMultiFrame(framePaths);

      // Cleanup frame files
      for (final path in framePaths) {
        try { await File(path).delete(); } catch (_) {}
      }
      framePaths.clear();

      if (!mounted || _phase != PresensiPhase.passiveCheck) return;

      if (result == null) {
        debugPrint('⚠️ [PASSIVE] Server unreachable, skipping to active');
        _passiveCheckTimer?.cancel();
        _advanceToActiveLiveness();
        return;
      }

      if (!result.faceDetected) {
        setState(() {
          _livenessScore = 0.0;
          _consecutiveRealCount = 0;
          _statusText = "Tidak ada wajah terdeteksi ❌";
        });
      } else if (result.isReal) {
        _consecutiveRealCount++;
        setState(() {
          _livenessScore = result.score;
          _statusText =
              "🛡️ Anti-Spoofing: REAL ✅ (${(_livenessScore * 100).toStringAsFixed(0)}%)"
              "\n$_consecutiveRealCount/$_requiredConsecutiveReal verifikasi...";
        });

        if (_consecutiveRealCount >= _requiredConsecutiveReal) {
          _passiveCheckTimer?.cancel();
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _advanceToActiveLiveness();
        }
      } else {
        // SPOOF DETECTED
        _consecutiveRealCount = 0;
        setState(() {
          _livenessScore = result.score;
          _statusText =
              "🚫 SPOOFING TERDETEKSI! (${(_livenessScore * 100).toStringAsFixed(0)}%)"
              "\nGunakan wajah asli Anda";
        });
      }
    } catch (e) {
      debugPrint("❌ [PASSIVE] Error: $e");
    }
    _isPassiveChecking = false;
  }

  // ═══════════════════════════════════════════
  // PHASE 2: ACTIVE LIVENESS (ML Kit)
  // ═══════════════════════════════════════════
  void _advanceToActiveLiveness() {
    if (!mounted) return;
    _passiveCheckTimer?.cancel();
    setState(() {
      _phase = PresensiPhase.activeLiveness;
      _hasBlinked = false;
      _hasTurnedHead = false;
      _statusText = "Kedipkan mata & putar kepala";
    });
    _startFaceDetection();
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || _phase != PresensiPhase.activeLiveness) return;
      _isDetecting = true;

      try {
        final faces = await _detectFaces(image);
        if (faces.isNotEmpty) {
          final Face targetFace = faces.reduce((a, b) {
            final areaA = a.boundingBox.width * a.boundingBox.height;
            final areaB = b.boundingBox.width * b.boundingBox.height;
            return areaA >= areaB ? a : b;
          });
          _validateActiveLiveness(targetFace);
        } else {
          if (mounted) setState(() => _statusText = "Tidak Ada Wajah ❌");
        }
      } catch (e) {
        debugPrint("⚠️ Error Face Detection: $e");
      }
      _isDetecting = false;
    });
  }

  InputImageRotation _rotationFromSensorOrientation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0: return InputImageRotation.rotation0deg;
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  Uint8List _convertYUV420toNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final Uint8List nv21Image = Uint8List(ySize + uvSize);
    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];

    int index = 0;
    for (int row = 0; row < height; row++) {
      final int rowOffset = row * planeY.bytesPerRow;
      nv21Image.setRange(index, index + width, planeY.bytes, rowOffset);
      index += width;
    }

    final int chromaRowStride = planeU.bytesPerRow;
    final int chromaPixelStride = planeU.bytesPerPixel!;
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int uvOffset = row * chromaRowStride + col * chromaPixelStride;
        nv21Image[index++] = planeV.bytes[uvOffset];
        nv21Image[index++] = planeU.bytes[uvOffset];
      }
    }
    return nv21Image;
  }

  Future<List<Face>> _detectFaces(CameraImage image) async {
    try {
      final camera = _cameraController!.description;
      final rotation = _rotationFromSensorOrientation(camera.sensorOrientation);
      final nv21Bytes = _convertYUV420toNV21(image);
      final inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      debugPrint("❌ _detectFaces error: $e");
      return [];
    }
  }

  void _validateActiveLiveness(Face face) {
    double? leftEye = face.leftEyeOpenProbability;
    double? rightEye = face.rightEyeOpenProbability;
    double headTurn = face.headEulerAngleY ?? 0;

    if (leftEye != null && rightEye != null) {
      if (leftEye < 0.3 && rightEye < 0.3) _hasBlinked = true;
    }
    if (headTurn > 15 || headTurn < -15) _hasTurnedHead = true;

    if (_hasBlinked && _hasTurnedHead) {
      _startCountdown();
    } else {
      String hint = '';
      if (!_hasBlinked && !_hasTurnedHead) {
        hint = 'Kedipkan mata & putar kepala';
      } else if (!_hasBlinked) {
        hint = 'Kedipkan mata Anda 👁️';
      } else {
        hint = 'Putar kepala ke samping ↔️';
      }
      if (mounted) setState(() => _statusText = hint);
    }
  }

  // ═══════════════════════════════════════════
  // PHASE 3: COUNTDOWN → CAPTURE → UPLOAD
  // ═══════════════════════════════════════════
  void _startCountdown() async {
    if (_phase == PresensiPhase.countdown) return;

    setState(() {
      _phase = PresensiPhase.countdown;
      _countdownValue = 3;
      _statusText = "Liveness Verified ✅";
    });

    // Stop image stream if it was started (Phase 2 may have been skipped)
    try {
      await _cameraController!.stopImageStream();
    } catch (_) {
      // Image stream was never started (anti-spoofing bypass) — safe to ignore
    }

    for (int i = 3; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdownValue = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    await _captureAndUpload();
  }

  Future<void> _captureAndUpload() async {
    setState(() {
      _phase = PresensiPhase.uploading;
      _statusText = "⏳ Memproses foto...";
    });

    try {
      final croppedPath = await _takeAndCropFacePicture();
      if (croppedPath != null) {
        await _uploadPhoto(File(croppedPath));
      } else {
        _showError("Gagal memproses foto wajah");
      }
    } catch (e) {
      debugPrint("❌ Gagal capture/upload: $e");
      _showError("Gagal memproses foto: ${e.toString().split('\n').first}");
    }
  }

  Future<void> _uploadPhoto(File photoFile) async {
    setState(() => _statusText = "⏳ Mengunggah foto...");

    try {
      final result = await ApiService.predictFace(photoFile);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HasilView(result: result),
        ),
      );
    } on DeviceUnboundException catch (e) {
      await _handleDeviceUnbound(e.message);
    } on ApiError catch (e) {
      _showError(e.error);
    } catch (e) {
      _showError("Upload gagal: ${e.toString().split('\n').first}");
    }
  }

  Future<String?> _takeAndCropFacePicture() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final imagePath = join(tempDir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      final XFile file = await _cameraController!.takePicture();
      await file.saveTo(imagePath);

      final inputImage = InputImage.fromFilePath(imagePath);
      final detectorOptions = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      );
      final faceDetector = FaceDetector(options: detectorOptions);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint("⚠️ No face during crop — using full image");
        return imagePath;
      }

      final face = faces.reduce((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaA >= areaB ? a : b;
      });
      final boundingBox = face.boundingBox;

      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return null;

      final x = boundingBox.left.toInt().clamp(0, originalImage.width - 1);
      final y = boundingBox.top.toInt().clamp(0, originalImage.height - 1);
      final width = boundingBox.width.toInt().clamp(1, originalImage.width - x);
      final height = boundingBox.height.toInt().clamp(1, originalImage.height - y);

      final cropped = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
      final croppedPath = join(tempDir.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
      File(croppedPath).writeAsBytesSync(img.encodeJpg(cropped));
      return croppedPath;
    } catch (e) {
      debugPrint("❌ Error cropping wajah: $e");
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // ERROR HANDLING & RESET
  // ═══════════════════════════════════════════
  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = PresensiPhase.error;
      _errorMessage = message;
    });
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(seconds: 5), _resetState);
  }

  void _resetState() async {
    if (!mounted) return;
    _errorResetTimer?.cancel();
    _passiveCheckTimer?.cancel();

    setState(() {
      _phase = PresensiPhase.faceDetection;
      _isFaceDetected = false;
      _hasBlinked = false;
      _hasTurnedHead = false;
      _isDetecting = false;
      _isPassiveChecking = false;
      _isGatekeeperProcessing = false;
      _errorMessage = '';
      _livenessScore = 0.0;
      _consecutiveRealCount = 0;
      _statusText = "Arahkan wajah ke kamera 📷";
    });

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        try { _cameraController!.stopImageStream(); } catch (_) {}
        // ── Always restart from Phase 0 (Face Gatekeeper) ──
        _startFaceGatekeeper();
      } catch (e) {
        debugPrint("⚠️ Error restarting: $e");
      }
    }
  }

  @override
  

  // ═══════════════════════════════════════════
  // ADMIN UNLOCK — Navigate to separate view (avoids CameraException)
  // ═══════════════════════════════════════════
  Future<void> _handleAdminUnlock() async {
    // 1. Stop all timers and camera
    _passiveCheckTimer?.cancel();
    _errorResetTimer?.cancel();

    // 2. Dispose camera completely to free hardware
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try { await _cameraController!.stopImageStream(); } catch (_) {}
      await _cameraController!.dispose();
      _cameraController = null;
    }

    if (!mounted) return;

    // 3. Navigate to AdminUnlockView (has its own camera)
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminUnlockView()),
    );

    // 4. Reinitialize camera when returning from admin view
    if (mounted) {
      setState(() {
        _phase = PresensiPhase.faceDetection;
        _statusText = 'Arahkan wajah ke kamera 📷';
        _hasBlinked = false;
        _hasTurnedHead = false;
        _consecutiveRealCount = 0;
      });
      await _initializeCamera();
    }
  }

  /// Force-logout when device is unbound/deleted
  Future<void> _handleDeviceUnbound(String message) async {
    // Clear binding state
    await AppConfig.setIsBound(false);
    await AppConfig.setDeviceSn('');
    await AppConfig.setBoundOpdName('');

    // Stop camera
    _passiveCheckTimer?.cancel();
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try { await _cameraController!.stopImageStream(); } catch (_) {}
      await _cameraController!.dispose();
      _cameraController = null;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Navigate to root → SplashRouter redirects to ActivationView
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  // ═══════════════════════════════════════════
  // EMERGENCY HATCH — 7 rapid taps on OPD name
  // ═══════════════════════════════════════════
  void _handleEmergencyTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds > 1000) {
      _emergencyTapCount = 0;
    }
    _emergencyTapCount++;
    _lastTapTime = now;

    if (_emergencyTapCount >= 7) {
      _emergencyTapCount = 0;
      _showEmergencyPinDialog();
    }
  }

  void _showEmergencyPinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Emergency Access', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan PIN darurat untuk membuka pengaturan.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '••••••',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text == '999999') {
                Navigator.pop(ctx);
                // Pause camera, go to settings
                _pauseCameraAndNavigate(const SettingsView());
              } else {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN salah.'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('Buka', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Pause camera, navigate to a page, reinitialize on return
  Future<void> _pauseCameraAndNavigate(Widget page) async {
    _passiveCheckTimer?.cancel();
    _errorResetTimer?.cancel();
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try { await _cameraController!.stopImageStream(); } catch (_) {}
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (!mounted) return;
    setState(() {});

    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    // Reinitialize camera on return
    if (mounted) {
      setState(() {
        _phase = PresensiPhase.faceDetection;
        _statusText = 'Arahkan wajah ke kamera 📷';
        _hasBlinked = false;
        _hasTurnedHead = false;
        _consecutiveRealCount = 0;
      });
      await _initializeCamera();
    }
  }

  // ═══════════════════════════════════════════
  // BUILD UI — Card-Based Layout
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final shortSide = mq.shortestSide;  // ~360 on phone, ~600+ on tablet
    final cameraHeight = mq.height * 0.62;

    // ── Responsive scale factors ──
    final double ovalW = shortSide * 0.50;  // face guide oval width
    final double ovalH = ovalW * 1.32;      // ~4:3 face aspect ratio
    final double ovalRadius = ovalW * 0.55;
    final double headerFontSize = shortSide * 0.042;
    final double headerIconSize = shortSide * 0.055;
    final double padH = shortSide * 0.04;   // horizontal padding

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Listener(
        onPointerDown: (_) => _resetIdleTimer(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // ── TOP HEADER BAR ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(padH * 2.5, padH * 0.6, padH * 0.6, 0), // Extra left padding to avoid back button overlap
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Presensi Wajah',
                              style: TextStyle(color: Colors.white, fontSize: headerFontSize, fontWeight: FontWeight.bold)),
                        ),
                        // Hidden admin gear (almost invisible)
                        Opacity(
                          opacity: 0.08,
                          child: IconButton(
                            icon: Icon(Icons.settings, color: Colors.white, size: headerIconSize * 0.8),
                            onPressed: _handleAdminUnlock,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: padH * 0.4),

                  // ── CAMERA CARD (top ~62%) ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    child: SizedBox(
                      height: cameraHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(shortSide * 0.05),
                        child: _cameraController == null || !_cameraController!.value.isInitialized
                            ? Container(
                                color: Colors.black,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(color: Colors.white54),
                                      SizedBox(height: padH * 0.6),
                                      Text('Memuat kamera...',
                                          style: TextStyle(color: Colors.white54, fontSize: shortSide * 0.032)),
                              ],
                            ),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            // Camera preview — scaled to fill card
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize!.height,
                                height: _cameraController!.value.previewSize!.width,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),

                            // Oval face guide (responsive)
                            Center(
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, _) {
                                  return Container(
                                    width: ovalW,
                                    height: ovalH,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _getOvalColor(),
                                        width: 2.5 + (_pulseController.value * 0.5),
                                      ),
                                      borderRadius: BorderRadius.circular(ovalRadius),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Phase steps indicator (top inside camera)
                            Positioned(
                              top: padH * 0.4, left: padH * 0.4, right: padH * 0.4,
                              child: _buildPhaseIndicator(),
                            ),

                            // Spoof warning overlay
                            if (_phase == PresensiPhase.passiveCheck &&
                                _livenessScore > 0 &&
                                _livenessScore < AntiSpoofService.livenessThreshold)
                              _buildSpoofOverlay(),

                            // Countdown overlay
                            if (_phase == PresensiPhase.countdown) _buildCountdownOverlay(),

                            // Upload overlay
                            if (_phase == PresensiPhase.uploading) _buildUploadOverlay(),

                            // Error overlay
                            if (_phase == PresensiPhase.error) _buildErrorOverlay(),
                          ],
                        ),
                ),
              ),
            ),

            // ── BOTTOM STATUS PANEL (~38%) ──
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padH, padH * 0.6, padH, padH * 0.4),
                child: Column(
                  children: [
                    // Liveness checklist
                    _buildChecklist(),

                    SizedBox(height: padH * 0.6),

                    // Status text
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padH * 0.6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(12),
                        borderRadius: BorderRadius.circular(shortSide * 0.035),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Text(_statusText,
                          style: TextStyle(color: Colors.white, fontSize: shortSide * 0.038),
                          textAlign: TextAlign.center),
                    ),

                    const Spacer(),

                    // OPD Name (7-tap emergency hatch target)
                    GestureDetector(
                      onTap: _handleEmergencyTap,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _opdName,
                          style: TextStyle(
                            color: Colors.white.withAlpha(80),
                            fontSize: shortSide * 0.028,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 2),
                    Text(
                      'Smart Presensi ASN \u2014 Diskominfo Kab. Tangerang',
                      style: TextStyle(color: Colors.white.withAlpha(40), fontSize: shortSide * 0.022),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      
      // Floating Back Button (Top Left)
      Positioned(
        top: padH * 0.4,
        left: padH * 0.4,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _idleTimer?.cancel();
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(shortSide * 0.08),
              child: Container(
                padding: EdgeInsets.all(shortSide * 0.025),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back, color: Colors.white, size: headerIconSize),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
),
);
}

  // ═══════════════════════════════════════════
  // UI WIDGETS
  // ═══════════════════════════════════════════
  Color _getOvalColor() {
    switch (_phase) {
      case PresensiPhase.faceDetection:
        return _isFaceDetected
            ? Colors.greenAccent
            : Colors.white.withValues(alpha: 0.4);
      case PresensiPhase.passiveCheck:
        return _consecutiveRealCount > 0
            ? Colors.greenAccent
            : Colors.amberAccent.withValues(alpha: 0.6);
      case PresensiPhase.activeLiveness:
        return (_hasBlinked && _hasTurnedHead)
            ? Colors.green
            : Colors.white.withValues(alpha: 0.6);
      case PresensiPhase.countdown:
        return Colors.green;
      default:
        return Colors.white.withValues(alpha: 0.4);
    }
  }

  Widget _buildPhaseIndicator() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s * 0.025, vertical: s * 0.018),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(s * 0.03),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _phaseStep(Icons.face, 'Deteksi',
              isActive: _phase == PresensiPhase.faceDetection,
              isDone: _phase != PresensiPhase.faceDetection && _phase != PresensiPhase.error),
          Padding(padding: EdgeInsets.only(bottom: s * 0.025),
              child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04)),
          _phaseStep(Icons.shield_outlined, 'Anti-Spoof',
              isActive: _phase == PresensiPhase.passiveCheck,
              isDone: _phase == PresensiPhase.activeLiveness ||
                      _phase == PresensiPhase.countdown ||
                      _phase == PresensiPhase.uploading),
          Padding(padding: EdgeInsets.only(bottom: s * 0.025),
              child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04)),
          _phaseStep(Icons.face_retouching_natural, 'Liveness',
              isActive: _phase == PresensiPhase.activeLiveness,
              isDone: _phase == PresensiPhase.countdown || _phase == PresensiPhase.uploading),
          Padding(padding: EdgeInsets.only(bottom: s * 0.025),
              child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04)),
          _phaseStep(Icons.camera_alt, 'Presensi',
              isActive: _phase == PresensiPhase.countdown || _phase == PresensiPhase.uploading,
              isDone: false),
        ],
      ),
    );
  }

  Widget _phaseStep(IconData icon, String label, {required bool isActive, required bool isDone}) {
    final s = MediaQuery.of(context).size.shortestSide;
    final color = isDone ? Colors.greenAccent : (isActive ? Colors.amberAccent : Colors.white30);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isDone ? Icons.check_circle : icon, color: color, size: s * 0.05),
        SizedBox(height: s * 0.005),
        Text(label, style: TextStyle(color: color, fontSize: s * 0.026, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildChecklist() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s * 0.04, vertical: s * 0.025),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(s * 0.035),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _checkItem('Anti-Spoof',
              done: _phase != PresensiPhase.passiveCheck && _phase != PresensiPhase.error,
              inProgress: _consecutiveRealCount > 0 && _phase == PresensiPhase.passiveCheck),
          SizedBox(width: s * 0.04),
          _checkItem('Kedip', done: _hasBlinked),
          SizedBox(width: s * 0.04),
          _checkItem('Putar', done: _hasTurnedHead),
        ],
      ),
    );
  }

  Widget _checkItem(String label, {bool done = false, bool inProgress = false}) {
    final s = MediaQuery.of(context).size.shortestSide;
    final color = done ? Colors.greenAccent : (inProgress ? Colors.amberAccent : Colors.white54);
    final icon = done
        ? Icons.check_circle
        : (inProgress ? Icons.timelapse : Icons.radio_button_unchecked);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: s * 0.045),
        SizedBox(width: s * 0.01),
        Text(label, style: TextStyle(color: color, fontSize: s * 0.032)),
      ],
    );
  }

  Widget _buildSpoofOverlay() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      color: Colors.red.withValues(alpha: 0.3),
      child: Center(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: s * 0.08),
          padding: EdgeInsets.symmetric(horizontal: s * 0.06, vertical: s * 0.05),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(s * 0.04),
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_bad, color: Colors.redAccent, size: s * 0.16),
              SizedBox(height: s * 0.03),
              Text('\u26a0\ufe0f SPOOFING TERDETEKSI',
                  style: TextStyle(color: Colors.redAccent, fontSize: s * 0.055, fontWeight: FontWeight.bold)),
              SizedBox(height: s * 0.02),
              Text('Skor: ${(_livenessScore * 100).toStringAsFixed(1)}% (min. 45%)',
                  style: TextStyle(color: Colors.white70, fontSize: s * 0.035)),
              SizedBox(height: s * 0.02),
              Text('Gunakan wajah asli Anda.\nFoto atau layar tidak diizinkan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: s * 0.04)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tetap diam...',
                style: TextStyle(color: Colors.white, fontSize: s * 0.055, fontWeight: FontWeight.w300)),
            SizedBox(height: s * 0.05),
            TweenAnimationBuilder<double>(
              key: ValueKey(_countdownValue),
              tween: Tween(begin: 1.5, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Text('$_countdownValue',
                      style: TextStyle(color: Colors.white, fontSize: s * 0.25, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOverlay() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            SizedBox(height: s * 0.05),
            Text("Mengunggah & memproses...",
                style: TextStyle(color: Colors.white, fontSize: s * 0.045)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: s * 0.08),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: s * 0.18),
              SizedBox(height: s * 0.04),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: s * 0.05, fontWeight: FontWeight.w500)),
              SizedBox(height: s * 0.06),
              ElevatedButton.icon(
                onPressed: _resetState,
                icon: const Icon(Icons.refresh),
                label: Text('Coba Lagi', style: TextStyle(fontSize: s * 0.04)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: s * 0.08, vertical: s * 0.035),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s * 0.03)),
                ),
              ),
              SizedBox(height: s * 0.03),
              Text('Otomatis reset dalam 5 detik...',
                  style: TextStyle(color: Colors.white54, fontSize: s * 0.032)),
            ],
          ),
        ),
      ),
    );
  }
}
