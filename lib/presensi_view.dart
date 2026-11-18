import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

import 'config/app_config.dart';
import 'services/api_service.dart';
import 'services/anti_spoof_service.dart';
import 'services/offline_sync_service.dart';
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
  bool _hasEyesReopened = false;  // Mata harus terbuka lagi setelah blink
  bool _hasTurnedHead = false;
  InputImageRotation? _lastValidRotation; // Rotasi kamera yang terbukti mendeteksi wajah
  int _noFaceConsecutiveCount = 0; // Menghindari flickering status jika 1 frame drop

  // ── Phase 2b: Camera Stabilization (Anti-Shake) ──
  Offset? _lastFaceCenter;        // Center of face bounding box (prev frame)
  bool _isCameraStable = true;    // False jika device goyang
  int _stableFrameCount = 0;      // Counter frame stabil berturut-turut
  static const int _requiredStableFrames = 5;   // Min 5 frame stabil
  static const double _maxBboxShift = 15.0;      // Max pixel shift allowed

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

  // ── Manual Camera Rotation (untuk tablet Samsung / kiosk display) ──
  int _manualRotationQuarterTurns = 0;

  /// Restart bersih kamera dan reset state machine ke Phase 0 (Face Gatekeeper).
  /// Menjamin stream lama dihentikan, buffer kamera bersih, dan deteksi dimulai ulang.
  Future<void> _cleanRestartCamera() async {
    if (!mounted) return;
    debugPrint('🔄 [Camera] Clean restart in progress...');

    _passiveCheckTimer?.cancel();
    _errorResetTimer?.cancel();
    _resetIdleTimer();

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _phase = PresensiPhase.faceDetection;
        _isFaceDetected = false;
        _hasBlinked = false;
        _hasEyesReopened = false;
        _hasTurnedHead = false;
        _isDetecting = false;
        _isPassiveChecking = false;
        _isGatekeeperProcessing = false;
        _errorMessage = '';
        _livenessScore = 0.0;
        _consecutiveRealCount = 0;
        _lastFaceCenter = null;
        _isCameraStable = true;
        _stableFrameCount = 0;
        _noFaceConsecutiveCount = 0;
        _lastValidRotation = null;
        _statusText = "Arahkan wajah ke kamera 📷";
      });
    }

    // Delay singkat agar HAL kamera Android menyelesaikan sesi sebelumnya
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    _startFaceGatekeeper();
  }

  void _toggleCameraRotation() {
    setState(() {
      _manualRotationQuarterTurns = (_manualRotationQuarterTurns + 1) % 4;
      _statusText = "Menyesuaikan orientasi kamera...";
    });
    debugPrint('🔄 [Camera] Rotation diubah manual: ${_manualRotationQuarterTurns * 90}°');
    _cleanRestartCamera();
  }

  int _getDisplayRotationQuarterTurns() {
    final camera = _cameraController?.description;
    if (camera == null) return _manualRotationQuarterTurns;

    // Deteksi sensor orientation:
    // Smartphone front camera: sensorOrientation = 270 (atau 90)
    // Tablet Samsung front camera (di bezel landscape seperti SM-X526B): sensorOrientation = 0
    final isTabletLandscapeSensor = camera.sensorOrientation == 0;
    
    // Apakah tampilan jendela/layar sedang vertikal (portrait)?
    final isPortraitDisplay = MediaQuery.of(context).size.height >= MediaQuery.of(context).size.width;

    int autoTurns = 0;
    if (isTabletLandscapeSensor && isPortraitDisplay) {
      // Tablet sensor landscape tapi dipakai di layar portrait (seperti Samsung SM-X526B):
      // Putar 90 derajat searah jarum jam agar tegak
      autoTurns = 1;
    }

    return (autoTurns + _manualRotationQuarterTurns) % 4;
  }

  /// Memastikan orientasi file foto tegak lurus (upright) sesuai tampilan.
  /// Memutar gambar menggunakan package:image dengan EXIF baking dan rotasi tampilan.
  Future<String> _ensureImageUpright(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return imagePath;

      // 1. Bake EXIF orientation ke raw pixels (otomatis tegak lurus sesuai sensor & device)
      decoded = img.bakeOrientation(decoded);

      // 2. Terapkan rotasi kompensasi HANYA jika pengguna sengaja memutar kamera manual
      if (_manualRotationQuarterTurns != 0) {
        decoded = img.copyRotate(decoded, angle: _manualRotationQuarterTurns * 90);
      }

      final rotatedBytes = img.encodeJpg(decoded, quality: 95);
      await file.writeAsBytes(rotatedBytes);
      return imagePath;
    } catch (e) {
      debugPrint("⚠️ [ImageRotate] Gagal memproses gambar $imagePath: $e");
      return imagePath;
    }
  }

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

  /// Reset idle timer. DINONAKTIFKAN SEMENTARA sesuai permintaan user
  /// agar halaman presensi tidak otomatis tertutup saat testing/kiosk.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    // Auto-close dinonaktifkan sementara
  }

  /// Cancel idle timer sepenuhnya (saat countdown/upload/processing).
  /// Timer TIDAK boleh jalan selama API call.
  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
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
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // ── Cache the anti-spoofing config once ──
      _antiSpoofEnabled = await AppConfig.getAntiSpoofingEnabled();
      debugPrint('🛡️ [Config] anti_spoofing_enabled = $_antiSpoofEnabled');

      setState(() {});

      // ── OFFLINE-SYNC: Try syncing any pending offline records ──
      OfflineSyncService.syncPendingAttendance().then((synced) {
        if (synced > 0) {
          debugPrint('📶 [Boot] Synced $synced pending offline records');
        }
      }).catchError((_) {
        debugPrint('📶 [Boot] Server unreachable, will retry later');
      });

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
          // Face found → reset idle timer & advance
          _resetIdleTimer();
          debugPrint('👤 [Gatekeeper] Face detected! Advancing...');
          await _cameraController!.stopImageStream();
          if (!mounted) return;
          setState(() => _isFaceDetected = true);
          _onFaceGatekeeperTriggered();
        } else {
          // No face — keep scanning (idle timer tetap berjalan)
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
  /// Anti-spoofing toggle ONLY controls Passive Check (server-side).
  /// Active Liveness (blink + head turn) is ALWAYS required.
  void _onFaceGatekeeperTriggered() {
    if (!_antiSpoofEnabled) {
      // Anti-spoofing OFF → skip Passive Check, but STILL require Active Liveness
      debugPrint('🛡️ [Gatekeeper] Anti-spoofing OFF → skip passive, go to ACTIVE liveness');
      _advanceToActiveLiveness();
    } else {
      // Anti-spoofing ON → run full pipeline (Passive → Active → Capture)
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
        final uprightPath = await _ensureImageUpright(xFile.path);
        framePaths.add(uprightPath);
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
      _hasEyesReopened = false;
      _hasTurnedHead = false;
      _lastFaceCenter = null;
      _isCameraStable = true;
      _stableFrameCount = 0;
      _statusText = "Tahan kamera stabil, lalu kedipkan mata 👁️";
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
        if (!mounted || _phase != PresensiPhase.activeLiveness) return;

        if (faces.isNotEmpty) {
          _noFaceConsecutiveCount = 0;
          final Face targetFace = faces.reduce((a, b) {
            final areaA = a.boundingBox.width * a.boundingBox.height;
            final areaB = b.boundingBox.width * b.boundingBox.height;
            return areaA >= areaB ? a : b;
          });
          _validateActiveLiveness(targetFace);
        } else {
          _noFaceConsecutiveCount++;
          // Jangan langsung menghapus instruksi kedip/liveness hanya karena 1 frame drop.
          // Hanya tampilkan peringatan jika sudah 8+ frame berturut-turut (~0.8 detik) tidak ada wajah sama sekali.
          if (_noFaceConsecutiveCount >= 8 && mounted) {
            setState(() => _statusText = "Arahkan wajah ke kamera 📷");
          }
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

  /// Rotasi input ML Kit yang 100% konsisten dengan rotasi visual tampilan.
  /// Menghindari desinkronisasi atau double-counting orientasi perangkat.
  InputImageRotation _computeInputRotation(CameraDescription camera) {
    final effectiveQuarterTurns = _getDisplayRotationQuarterTurns();
    final sensor = camera.sensorOrientation;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (sensor + effectiveQuarterTurns * 90) % 360
        : (sensor - effectiveQuarterTurns * 90 + 360) % 360;
    return _rotationFromSensorOrientation(degrees);
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
      if (rowOffset + width <= planeY.bytes.length) {
        nv21Image.setRange(index, index + width, planeY.bytes, rowOffset);
      }
      index += width;
    }

    final int chromaRowStride = planeU.bytesPerRow;
    final int chromaPixelStride = planeU.bytesPerPixel ?? 1;
    final int vLen = planeV.bytes.length;
    final int uLen = planeU.bytes.length;

    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int uvOffset = row * chromaRowStride + col * chromaPixelStride;
        if (uvOffset < vLen && uvOffset < uLen && index + 1 < nv21Image.length) {
          nv21Image[index++] = planeV.bytes[uvOffset];
          nv21Image[index++] = planeU.bytes[uvOffset];
        }
      }
    }
    return nv21Image;
  }

  InputImage? _buildInputImage(CameraImage image, InputImageRotation rotation) {
    // 1. Jika stream kamera native NV21 (single plane)
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // 2. Jika stream multi-plane (YUV420 fallback)
    try {
      final nv21Bytes = _convertYUV420toNV21(image);
      return InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    } catch (e) {
      debugPrint("⚠️ Error building InputImage: $e");
      return null;
    }
  }

  Future<List<Face>> _detectFaces(CameraImage image) async {
    try {
      final camera = _cameraController!.description;
      final defaultRotation = _computeInputRotation(camera);

      // 1. Coba rotasi yang sudah terbukti mendeteksi wajah atau rotasi default tampilan
      final primaryRotation = _lastValidRotation ?? defaultRotation;
      final primaryInput = _buildInputImage(image, primaryRotation);
      if (primaryInput != null) {
        final faces = await _faceDetector.processImage(primaryInput);
        if (faces.isNotEmpty) {
          _lastValidRotation = primaryRotation;
          return faces;
        }
      }

      // 2. Jika belum menemukan wajah, lakukan probing otomatis ke 3 rotasi lainnya
      // [0°, 90°, 270°, 180°] agar kompatibel 100% di semua device, DeX, dan Samsung Pop-up Window
      const candidateRotations = [
        InputImageRotation.rotation0deg,
        InputImageRotation.rotation90deg,
        InputImageRotation.rotation270deg,
        InputImageRotation.rotation180deg,
      ];

      for (final rot in candidateRotations) {
        if (rot == primaryRotation) continue;
        final probeInput = _buildInputImage(image, rot);
        if (probeInput != null) {
          final probeFaces = await _faceDetector.processImage(probeInput);
          if (probeFaces.isNotEmpty) {
            _lastValidRotation = rot;
            debugPrint('🎯 [MLKit] Mengunci rotasi kamera otomatis: ${rot.rawValue}°');
            return probeFaces;
          }
        }
      }

      return [];
    } catch (e) {
      debugPrint("❌ _detectFaces error: $e");
      return [];
    }
  }

  // ─── Camera Stabilization Check (Anti-Shake via Bounding Box) ───
  void _checkCameraStability(Face face) {
    final Rect bbox = face.boundingBox;
    final Offset currentCenter = Offset(
      bbox.left + bbox.width / 2,
      bbox.top + bbox.height / 2,
    );

    if (_lastFaceCenter != null) {
      final double shift = (currentCenter - _lastFaceCenter!).distance;
      if (shift > _maxBboxShift) {
        // Device goyang — reset counter
        _stableFrameCount = 0;
        if (_isCameraStable) {
          setState(() {
            _isCameraStable = false;
            // Tampilkan peringatan shake HANYA jika belum selesai challenge
            if (!(_hasBlinked && _hasEyesReopened && _hasTurnedHead)) {
              _statusText = "⚠️ Tahan kamera agar stabil";
            }
          });
        }
      } else {
        _stableFrameCount++;
        if (_stableFrameCount >= _requiredStableFrames && !_isCameraStable) {
          setState(() => _isCameraStable = true);
        }
      }
    }
    _lastFaceCenter = currentCenter;
  }

  void _validateActiveLiveness(Face face) {
    // ── Reset idle timer — user sedang aktif (wajah terdeteksi) ──
    _resetIdleTimer();

    // ── Step 0: Camera Stability Check ──
    _checkCameraStability(face);

    double? leftEye = face.leftEyeOpenProbability;
    double? rightEye = face.rightEyeOpenProbability;
    double headTurn = face.headEulerAngleY ?? 0;

    // ── SEQUENTIAL Challenge: Blink FIRST, then Head Turn ──
    // Step 1: Detect blink (toleran untuk kacamata & kondisi pencahayaan)
    if (!_hasBlinked) {
      bool isBlinking = false;
      if (leftEye != null && rightEye != null) {
        final avgOpen = (leftEye + rightEye) / 2.0;
        // Mata tertutup jika rata-rata < 0.35, atau salah satu mata < 0.28 (karena pantulan kacamata)
        if (avgOpen < 0.35 || leftEye < 0.28 || rightEye < 0.28) {
          isBlinking = true;
        }
      } else if (leftEye != null && leftEye < 0.35) {
        isBlinking = true;
      } else if (rightEye != null && rightEye < 0.35) {
        isBlinking = true;
      }

      if (isBlinking) {
        _hasBlinked = true;
        debugPrint('👁️ [Liveness] Blink terdeteksi! (L: $leftEye, R: $rightEye)');
      }
      if (mounted && !_hasBlinked) {
        setState(() => _statusText = 'Kedipkan mata Anda 👁️');
      }
      return; // Jangan proses step lain sampai blink selesai
    }

    // Step 2: Confirm eyes REOPENED after blink (anti-cheat: tutup mata terus ≠ blink)
    if (_hasBlinked && !_hasEyesReopened) {
      bool isReopened = false;
      if (leftEye != null && rightEye != null) {
        final avgOpen = (leftEye + rightEye) / 2.0;
        if (avgOpen > 0.45 || leftEye > 0.5 || rightEye > 0.5) {
          isReopened = true;
        }
      } else if (leftEye != null && leftEye > 0.45) {
        isReopened = true;
      } else if (rightEye != null && rightEye > 0.45) {
        isReopened = true;
      }

      if (isReopened) {
        _hasEyesReopened = true;
        debugPrint('👁️ [Liveness] Mata terbuka kembali! (L: $leftEye, R: $rightEye)');
      }
      if (mounted && !_hasEyesReopened) {
        setState(() => _statusText = 'Buka mata Anda kembali 👀');
      }
      return; // Tunggu mata terbuka
    }

    // Step 3: Head rotation (only AFTER confirmed blink)
    if (!_hasTurnedHead) {
      if (headTurn > 12 || headTurn < -12) {
        _hasTurnedHead = true;
        debugPrint('↔️ [Liveness] Head turn terdeteksi! (angle=$headTurn)');
      }
      if (mounted && !_hasTurnedHead) {
        setState(() => _statusText = 'Putar kepala ke samping ↔️');
      }
      return;
    }

    // ── ALL CHALLENGES PASSED ──
    // Final gate: camera harus stabil saat capture
    if (!_isCameraStable) {
      if (mounted) {
        setState(() => _statusText = '✅ Liveness OK! Tahan kamera stabil...');
      }
      return; // Tunggu kamera stabil
    }

    _startCountdown();
  }

  // ═══════════════════════════════════════════
  // PHASE 3: COUNTDOWN → CAPTURE → UPLOAD
  // ═══════════════════════════════════════════
  void _startCountdown() async {
    if (_phase == PresensiPhase.countdown) return;

    // ── CANCEL idle timer — user sedang aktif, jangan pop ──
    _cancelIdleTimer();

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
    // Pastikan idle timer tetap mati selama upload
    _cancelIdleTimer();

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

    // Simpan timestamp SEKARANG — jika nanti harus offline, waktu ini yang dikirim
    final captureTimestamp = DateTime.now().toIso8601String();

    try {
      final result = await ApiService.predictFace(photoFile);
      if (!mounted) return;

      // ── Upload berhasil — coba sync pending offline records di background ──
      OfflineSyncService.syncPendingAttendance().then((synced) {
        if (synced > 0) {
          debugPrint('📶 [Offline-Sync] Background sync: $synced records synced');
        }
      }).catchError((_) {});

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HasilView(result: result),
        ),
      );
    } on DeviceUnboundException catch (e) {
      await _handleDeviceUnbound(e.message);
    } on ApiError catch (e) {
      // Cek apakah error ini karena NETWORK (bukan server rejection)
      if (e.statusCode == 0) {
        // statusCode 0 = network-level error (timeout, connection refused, dll)
        await _storeOffline(photoFile, captureTimestamp);
      } else {
        // Server menolak (400/403/401/500) — tampilkan error normal
        _showError(e.error);
      }
    } catch (e) {
      // Catch-all: SocketException, dll
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socket') || errStr.contains('connection') ||
          errStr.contains('timeout') || errStr.contains('network')) {
        await _storeOffline(photoFile, captureTimestamp);
      } else {
        _showError("Upload gagal: ${e.toString().split('\n').first}");
      }
    }
  }

  /// Simpan presensi ke antrian offline dan tampilkan pesan ke user.
  Future<void> _storeOffline(File photoFile, String captureTimestamp) async {
    try {
      await OfflineSyncService.storePendingAttendance(
        photoFile: photoFile,
        localTimestamp: captureTimestamp,
      );
      final pendingCount = await OfflineSyncService.getPendingCount();
      if (!mounted) return;
      _showOfflineSavedMessage(pendingCount);
    } catch (e) {
      _showError("Gagal menyimpan offline: $e");
    }
  }

  /// Tampilkan pesan sukses offline (bukan error — presensi TERSIMPAN lokal).
  void _showOfflineSavedMessage(int pendingCount) {
    if (!mounted) return;
    _resetIdleTimer();
    setState(() {
      _phase = PresensiPhase.error; // reuse error phase for display
      _errorMessage = '📶 Internet terputus.\n'
          'Presensi disimpan secara lokal dan akan\n'
          'disinkronkan otomatis nanti.\n'
          '(Antrian: $pendingCount)';
    });
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(seconds: 5), _resetState);
  }

  Future<String?> _takeAndCropFacePicture() async {
    FaceDetector? faceDetector;
    try {
      final tempDir = await getTemporaryDirectory();
      final imagePath = join(tempDir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      final XFile file = await _cameraController!.takePicture();
      await file.saveTo(imagePath);

      // Pastikan file foto tegak lurus sesuai orientasi tampilan sebelum crop & upload
      await _ensureImageUpright(imagePath);

      final inputImage = InputImage.fromFilePath(imagePath);
      final detectorOptions = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      );
      faceDetector = FaceDetector(options: detectorOptions);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint("⚠️ [Crop] Wajah tidak terdeteksi via ML Kit saat crop — mengirim full image");
        return imagePath;
      }

      final face = faces.reduce((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaA >= areaB ? a : b;
      });
      final bb = face.boundingBox;

      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return imagePath;

      // ── SQUARE HEAD-CENTERED CROP DENGAN 1.55x MARGIN (ANTI-POTONG DAHI & RAMBUT) ──
      // cy digeser sedikit ke atas (0.40) agar dahi & rambut atas tidak terpotong
      final double cx = bb.left + bb.width / 2.0;
      final double cy = bb.top + bb.height * 0.40;

      final double maxSide = bb.width > bb.height ? bb.width : bb.height;
      final int side = (maxSide * 1.55).round().clamp(140, originalImage.height);

      int x1 = (cx - side / 2.0).round();
      int y1 = (cy - side / 2.0).round();
      int x2 = x1 + side;
      int y2 = y1 + side;

      // Geser jendela crop agar tetap 1:1 di dalam gambar tanpa memotong kepala
      if (x1 < 0) {
        x2 -= x1;
        x1 = 0;
      }
      if (y1 < 0) {
        y2 -= y1;
        y1 = 0;
      }
      if (x2 > originalImage.width) {
        final shift = x2 - originalImage.width;
        x1 = (x1 - shift).clamp(0, originalImage.width);
        x2 = originalImage.width;
      }
      if (y2 > originalImage.height) {
        final shift = y2 - originalImage.height;
        y1 = (y1 - shift).clamp(0, originalImage.height);
        y2 = originalImage.height;
      }

      final int width = (x2 - x1).clamp(1, originalImage.width);
      final int height = (y2 - y1).clamp(1, originalImage.height);

      final cropped = img.copyCrop(originalImage, x: x1, y: y1, width: width, height: height);
      final croppedPath = join(tempDir.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(croppedPath).writeAsBytes(img.encodeJpg(cropped, quality: 95));
      debugPrint("✅ [Crop] Wajah berhasil di-crop 1:1 persegi: ${width}x$height px");
      return croppedPath;
    } catch (e) {
      debugPrint("❌ Error cropping wajah: $e");
      return null;
    } finally {
      faceDetector?.close();
    }
  }

  // ═══════════════════════════════════════════
  // ERROR HANDLING & RESET
  // ═══════════════════════════════════════════
  void _showError(String message) {
    if (!mounted) return;
    // Restart idle timer saat error (user mungkin meninggalkan kiosk)
    _resetIdleTimer();
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
    // Restart idle timer saat kembali ke Phase 0
    _resetIdleTimer();

    setState(() {
      _phase = PresensiPhase.faceDetection;
      _isFaceDetected = false;
      _hasBlinked = false;
      _hasEyesReopened = false;
      _hasTurnedHead = false;
      _isDetecting = false;
      _isPassiveChecking = false;
      _isGatekeeperProcessing = false;
      _errorMessage = '';
      _livenessScore = 0.0;
      _consecutiveRealCount = 0;
      _lastFaceCenter = null;
      _isCameraStable = true;
      _stableFrameCount = 0;
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
  // BUILD UI — Modern Kiosk Face Verification Layout
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final isLandscape = mq.width > mq.height;
    final shortSide = mq.shortestSide;  // ~360 on phone, ~600+ on tablet

    // ── Responsive scale factors ──
    final double headerFontSize = shortSide * 0.042;
    final double headerIconSize = shortSide * 0.055;
    final double padH = shortSide * 0.04;   // horizontal padding

    Widget titleText() => Text(
          'Verifikasi Wajah Presensi',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: headerFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        );

    // ── CAMERA CARD with Modern ClipRRect (borderRadius: 28) ──
    Widget cameraCard({double? height}) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _isFaceDetected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.12),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            if (_isFaceDetected)
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 2,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: _cameraController == null || !_cameraController!.value.isInitialized
              ? Container(
                  color: const Color(0xFF1E293B),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF60A5FA)),
                        SizedBox(height: padH * 0.6),
                        Text(
                          'Menginisialisasi kamera biometrik...',
                          style: TextStyle(
                            color: const Color(0xFF94A3B8),
                            fontSize: shortSide * 0.032,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, cardConstraints) {
                    final cardW = cardConstraints.maxWidth;
                    // Skala oval dipatok 62% dari lebar card (bukan ukuran layar global tablet)
                    final double localOvalW = (cardW * 0.62).clamp(160.0, 380.0);
                    final double localOvalH = localOvalW * 1.32;
                    final double localOvalRadius = localOvalW * 0.55;

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Camera preview — orientation-aware, fills card without distortion
                        _buildCameraFeed(),

                        // Oval face guide (responsive terhadap ukuran card)
                        Center(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              return Container(
                                width: localOvalW,
                                height: localOvalH,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _getOvalColor(),
                                    width: 2.5 + (_pulseController.value * 0.5),
                                  ),
                                  borderRadius: BorderRadius.circular(localOvalRadius),
                                ),
                              );
                            },
                          ),
                        ),

                        // Phase steps indicator (top inside camera — hanya di portrait)
                        if (!isLandscape)
                          Positioned(
                            top: padH * 0.4,
                            left: padH * 0.4,
                            right: padH * 0.4,
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
                    );
                  },
                ),
        ),
      );
    }

   
    Widget statusCapsule() {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padH * 0.55),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isFaceDetected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: _isFaceDetected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isFaceDetected
                  ? Icons.face_retouching_natural
                  : Icons.camera_front_rounded,
              color: _isFaceDetected
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF94A3B8),
              size: shortSide * 0.045,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _statusText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: shortSide * 0.035,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    // ── Panel status (checklist + capsule + OPD + footer) ──
    List<Widget> statusPanel(Widget gap) => [
          // Liveness Dynamic Glowing Checklist
          _buildChecklist(),

          SizedBox(height: padH * 0.5),

          statusCapsule(),

          gap,

          // OPD Name (7-tap emergency hatch target)
          GestureDetector(
            onTap: _handleEmergencyTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                _opdName,
                style: TextStyle(
                  color: const Color(0xFF94A3B8),
                  fontSize: shortSide * 0.028,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 4),
          Text(
            'Smart Presensi ASN \u2014 Diskominfo Kab. Tangerang',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: shortSide * 0.022,
            ),
            textAlign: TextAlign.center,
          ),
        ];

    // ── PORTRAIT: Header → Camera (Proporsional 3:4) → Status ──
    Widget portraitBody() {
      // Pada portrait, batasi tinggi kamera agar proporsional 3:4 (anti-gepeng di tablet & HP)
      final double maxCardH = mq.height * 0.58;
      final double cardW = (maxCardH * (3 / 4)).clamp(0.0, mq.width - (padH * 2));
      final double cardH = cardW * (4 / 3);

      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padH * 0.4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [titleText()],
            ),
          ),
          SizedBox(height: padH * 0.2),
          Center(
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: cameraCard(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padH, padH * 0.5, padH, padH * 0.4),
              child: Column(
                children: statusPanel(const Spacer()),
              ),
            ),
          ),
        ],
      );
    }

    // ── LANDSCAPE (tablet): Header atas rapi, Kamera kiri (proporsional), Panel status kanan ──
    Widget landscapeBody() {
      return Column(
        children: [
          // ── TOP APP BAR (Dedicated untuk mode Landscape Tablet) ──
          Container(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padH * 0.35),
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
                // Tombol Kembali
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _idleTimer?.cancel();
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(shortSide * 0.08),
                    child: Container(
                      padding: EdgeInsets.all(shortSide * 0.022),
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: headerIconSize * 0.85),
                    ),
                  ),
                ),
                SizedBox(width: padH * 0.4),

                // Judul & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Verifikasi Wajah Presensi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: headerFontSize * 0.95,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Posisikan wajah Anda tepat di dalam area kamera untuk verifikasi biometrik',
                        style: TextStyle(
                          color: const Color(0xFF94A3B8),
                          fontSize: shortSide * 0.022,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Aksi Top Bar: Refresh + Putar + Pengaturan
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tombol Refresh Kamera
                    Tooltip(
                      message: 'Refresh Kamera & Deteksi',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _cleanRestartCamera,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.022),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.refresh_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: padH * 0.25),

                    // Tombol Putar Kamera
                    Tooltip(
                      message: 'Putar Orientasi Kamera',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _toggleCameraRotation,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.022),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.rotate_90_degrees_cw_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: padH * 0.25),

                    // Tombol Gear / Admin Unlock
                    Tooltip(
                      message: 'Pengaturan Kiosk',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleAdminUnlock,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.022),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.settings_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── KONTEN DUA KOLOM: Kamera Kiri & Panel Status Kanan ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padH * 0.4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Kolom Kiri: Kamera (Proporsional 3:4 portrait card di dalam landscape)
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: cameraCard(),
                      ),
                    ),
                  ),

                  SizedBox(width: padH * 0.7),

                  // Kolom Kanan: Panduan, Status Capsule, Checklist, OPD
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Tahapan Verifikasi
                            _buildPhaseIndicator(),

                            SizedBox(height: padH * 0.5),

                            // Dynamic Glowing Status Capsule
                            statusCapsule(),

                            SizedBox(height: padH * 0.5),

                            // Checklist Liveness
                            _buildChecklist(),

                            SizedBox(height: padH * 0.6),

                            // OPD Name (7-tap emergency hatch)
                            GestureDetector(
                              onTap: _handleEmergencyTap,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Text(
                                  _opdName,
                                  style: TextStyle(
                                    color: const Color(0xFF94A3B8),
                                    fontSize: shortSide * 0.028,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),
                            Text(
                              'Smart Presensi ASN \u2014 Diskominfo Kab. Tangerang',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: shortSide * 0.022,
                              ),
                              textAlign: TextAlign.center,
                            ),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900 Pure Dark Background
      body: Listener(
        onPointerDown: (_) => _resetIdleTimer(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            SafeArea(
              child: isLandscape ? landscapeBody() : portraitBody(),
            ),

            // ── TOMBOL MELAYANG HANYA UNTUK MODE PORTRAIT (HP) ──
            if (!isLandscape) ...[
              // FLOATING BACK BUTTON (TOP LEFT)
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
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: headerIconSize * 0.85),
                      ),
                    ),
                  ),
                ),
              ),

              // FLOATING BUTTONS: REFRESH, ROTATE & SETTINGS (TOP RIGHT)
              Positioned(
                top: padH * 0.4,
                right: padH * 0.4,
                child: SafeArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tombol Refresh Kamera
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _cleanRestartCamera,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.025),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.refresh_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: padH * 0.25),
                      // Tombol Putar Kamera
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _toggleCameraRotation,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.025),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.rotate_90_degrees_cw_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: padH * 0.25),
                      // Tombol Gear / Admin Unlock
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleAdminUnlock,
                          borderRadius: BorderRadius.circular(shortSide * 0.08),
                          child: Container(
                            padding: EdgeInsets.all(shortSide * 0.025),
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.settings_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: headerIconSize * 0.85,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Preview kamera yang 100% TIDAK TERDISTORSI (Anti-Gepeng) & Auto-Rotasi.
  /// Menjamin rasio intrinsik CameraPreview dan bounding box match sempurna.
  Widget _buildCameraFeed() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const SizedBox();
    }

    final int quarterTurns = _getDisplayRotationQuarterTurns();
    final double rawAr = _cameraController!.value.aspectRatio;
    final bool isScreenLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Aspect ratio intrinsik yang dipaksakan oleh widget CameraPreview:
    final double cameraPreviewRatio =
        isScreenLandscape ? rawAr : (1.0 / rawAr);

    // Menghilangkan letterbox total: SizedBox memiliki rasio PERSIS sama dengan CameraPreview
    // lalu diputar dengan RotatedBox dan discale oleh FittedBox(fit: BoxFit.cover)
    // sehingga 100% card terisi penuh tanpa garis hitam dan 100% anti-gepeng di HP maupun Tablet.
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

  // ═══════════════════════════════════════════
  // UI WIDGETS
  // ═══════════════════════════════════════════
  Color _getOvalColor() {
    switch (_phase) {
      case PresensiPhase.faceDetection:
        return _isFaceDetected
            ? const Color(0xFF10B981) // Emerald Green
            : Colors.white.withValues(alpha: 0.4);
      case PresensiPhase.passiveCheck:
        return _consecutiveRealCount > 0
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B).withValues(alpha: 0.7);
      case PresensiPhase.activeLiveness:
        return (_hasBlinked && _hasTurnedHead)
            ? const Color(0xFF10B981)
            : Colors.white.withValues(alpha: 0.6);
      case PresensiPhase.countdown:
        return const Color(0xFF10B981);
      default:
        return Colors.white.withValues(alpha: 0.4);
    }
  }

  Widget _buildPhaseIndicator() {
    final s = MediaQuery.of(context).size.shortestSide;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s * 0.025, vertical: s * 0.018),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _phaseStep(Icons.face, 'Deteksi',
              isActive: _phase == PresensiPhase.faceDetection,
              isDone: _phase != PresensiPhase.faceDetection && _phase != PresensiPhase.error),
          Padding(
            padding: EdgeInsets.only(bottom: s * 0.025),
            child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04),
          ),
          _phaseStep(Icons.shield_outlined, 'Anti-Spoof',
              isActive: _phase == PresensiPhase.passiveCheck,
              isDone: _phase == PresensiPhase.activeLiveness ||
                      _phase == PresensiPhase.countdown ||
                      _phase == PresensiPhase.uploading),
          Padding(
            padding: EdgeInsets.only(bottom: s * 0.025),
            child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04),
          ),
          _phaseStep(Icons.face_retouching_natural, 'Liveness',
              isActive: _phase == PresensiPhase.activeLiveness,
              isDone: _phase == PresensiPhase.countdown || _phase == PresensiPhase.uploading),
          Padding(
            padding: EdgeInsets.only(bottom: s * 0.025),
            child: Icon(Icons.chevron_right, color: Colors.white24, size: s * 0.04),
          ),
          _phaseStep(Icons.camera_alt_rounded, 'Presensi',
              isActive: _phase == PresensiPhase.countdown || _phase == PresensiPhase.uploading,
              isDone: false),
        ],
      ),
    );
  }

  Widget _phaseStep(IconData icon, String label, {required bool isActive, required bool isDone}) {
    final s = MediaQuery.of(context).size.shortestSide;
    final color = isDone
        ? const Color(0xFF10B981) // Emerald
        : (isActive ? const Color(0xFF60A5FA) : Colors.white30); // Sapphire light vs dim
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isDone ? Icons.check_circle_rounded : icon, color: color, size: s * 0.05),
        SizedBox(height: s * 0.005),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: s * 0.026,
            fontWeight: isDone || isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Modern Liveness Dynamic Glowing Chips
  Widget _buildChecklist() {
    final s = MediaQuery.of(context).size.shortestSide;
    final isAntiSpoofDone = _phase != PresensiPhase.passiveCheck && _phase != PresensiPhase.error;
    final isAntiSpoofActive = _phase == PresensiPhase.passiveCheck && _consecutiveRealCount > 0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s * 0.03, vertical: s * 0.02),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isFaceDetected
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: _isFaceDetected
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildGlowChip(
            label: 'Anti-Spoof',
            icon: Icons.shield_outlined,
            isDone: isAntiSpoofDone,
            isActive: isAntiSpoofActive,
          ),
          _buildGlowChip(
            label: 'Kedip',
            icon: Icons.visibility_outlined,
            isDone: _hasBlinked,
            isActive: _phase == PresensiPhase.activeLiveness && !_hasBlinked,
          ),
          _buildGlowChip(
            label: 'Putar',
            icon: Icons.sync_alt_rounded,
            isDone: _hasTurnedHead,
            isActive: _phase == PresensiPhase.activeLiveness && _hasBlinked && !_hasTurnedHead,
          ),
        ],
      ),
    );
  }

  Widget _buildGlowChip({
    required String label,
    required IconData icon,
    required bool isDone,
    required bool isActive,
  }) {
    final s = MediaQuery.of(context).size.shortestSide;
    final Color stateColor = isDone
        ? const Color(0xFF10B981) // Emerald
        : (isActive ? const Color(0xFF3B82F6) : const Color(0xFF64748B)); // Sapphire vs Slate

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: s * 0.025, vertical: s * 0.015),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.14)
            : (isActive ? const Color(0xFF2563EB).withValues(alpha: 0.18) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: stateColor.withValues(alpha: isDone || isActive ? 0.45 : 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : icon,
            color: stateColor,
            size: s * 0.042,
          ),
          SizedBox(width: s * 0.012),
          Text(
            label,
            style: TextStyle(
              color: isDone || isActive ? Colors.white : const Color(0xFF94A3B8),
              fontSize: s * 0.028,
              fontWeight: isDone || isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
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
              Text('Skor: ${(_livenessScore * 100).toStringAsFixed(1)}% (min. 65%)',
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
