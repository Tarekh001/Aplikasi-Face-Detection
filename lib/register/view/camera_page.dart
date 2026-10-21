import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import '../../config/app_theme.dart';

/// Guided multi-pose camera page with oval overlay and step-by-step flow.
/// Captures 5 photos in sequence, each with a specific pose instruction.
/// Supports switching between Front & Back cameras and manual 90° rotation
/// for seamless operation across smartphones and landscape/portrait tablets.
class GuidedCameraPage extends StatefulWidget {
  final CameraDescription camera;
  final List<CameraDescription>? cameras;
  final int startFromIndex;

  const GuidedCameraPage({
    required this.camera,
    this.cameras,
    this.startFromIndex = 0,
    super.key,
  });

  @override
  State<GuidedCameraPage> createState() => _GuidedCameraPageState();
}

class _GuidedCameraPageState extends State<GuidedCameraPage>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  late CameraDescription _currentCamera;

  late FaceDetector _faceDetector;
  late AnimationController _pulseController;
  Timer? _detectionTimer;

  final List<File> _capturedPhotos = [];
  int _currentPoseIndex = 0;
  bool _isFaceDetected = false;
  bool _isCapturing = false;
  bool _isDetecting = false;
  bool _isSwitchingCamera = false;
  int _manualRotationQuarterTurns = 0;

  // ── Pose data — clean, punchy human-readable instructions ──
  static const List<Map<String, dynamic>> _poses = [
    {'label': 'Hadap Depan', 'icon': Icons.person, 'desc': 'Pandang kamera, ekspresi netral'},
    {'label': 'Tersenyum', 'icon': Icons.sentiment_satisfied_alt, 'desc': 'Senyum natural ke kamera'},
    {'label': 'Toleh Kanan', 'icon': Icons.turn_right, 'desc': 'Toleh sedikit ke kanan Anda'},
    {'label': 'Toleh Kiri', 'icon': Icons.turn_left, 'desc': 'Toleh sedikit ke kiri Anda'},
    {'label': 'Dongak Atas', 'icon': Icons.north, 'desc': 'Angkat dagu sedikit ke atas'},
  ];

  @override
  void initState() {
    super.initState();
    _currentPoseIndex = widget.startFromIndex;
    _currentCamera = widget.camera;
    if (widget.cameras != null && widget.cameras!.isNotEmpty) {
      _cameras = List<CameraDescription>.from(widget.cameras!);
    }

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initCamera(_currentCamera);
  }

  Future<void> _initCamera(CameraDescription targetCamera) async {
    _detectionTimer?.cancel();
    if (mounted) {
      setState(() {
        _isSwitchingCamera = true;
        _isFaceDetected = false;
      });
    }

    // Tunggu sejenak apabila ada proses deteksi frame yang sedang berjalan
    int waitTicks = 0;
    while (_isDetecting && waitTicks < 10) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitTicks++;
    }

    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (_) {}
    }

    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }

      _currentCamera = targetCamera;
      final controller = CameraController(
        targetCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isSwitchingCamera = false;
      });

      _startPeriodicDetection();
    } catch (e) {
      debugPrint('⚠️ GuidedCameraPage init error: $e');
      if (mounted) {
        setState(() => _isSwitchingCamera = false);
      }
    }
  }

  Future<void> _switchCameraLens() async {
    if (_isCapturing || _isSwitchingCamera) return;
    if (_cameras.length < 2) {
      try {
        _cameras = await availableCameras();
      } catch (_) {}
      if (_cameras.length < 2) return;
    }

    final targetLens = _currentCamera.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final nextCamera = _cameras.firstWhere(
      (c) => c.lensDirection == targetLens,
      orElse: () => _cameras.firstWhere(
        (c) => c.name != _currentCamera.name,
        orElse: () => _cameras.first,
      ),
    );

    setState(() {
      _manualRotationQuarterTurns = 0;
    });

    await _initCamera(nextCamera);
  }

  void _toggleCameraRotation() {
    if (_isCapturing || _isSwitchingCamera) return;
    setState(() {
      _manualRotationQuarterTurns = (_manualRotationQuarterTurns + 1) % 4;
      _isFaceDetected = false;
    });
  }

  Future<void> _refreshCamera() async {
    if (_isCapturing || _isSwitchingCamera) return;
    await _initCamera(_currentCamera);
  }

  int _getDisplayRotationQuarterTurns() {
    final isTabletLandscapeSensor = _currentCamera.sensorOrientation == 0;
    final isPortraitDisplay =
        MediaQuery.of(context).size.height >= MediaQuery.of(context).size.width;

    int autoTurns = 0;
    if (isTabletLandscapeSensor && isPortraitDisplay) {
      autoTurns = 1;
    }

    return (autoTurns + _manualRotationQuarterTurns) % 4;
  }

  /// Memastikan orientasi file foto tegak lurus (upright) sesuai tampilan layar
  /// (menggabungkan EXIF baking + rotasi manual pengguna).
  Future<String> _ensureImageUpright(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return imagePath;

      // 1. Bake EXIF orientation ke raw pixels
      decoded = img.bakeOrientation(decoded);

      // 2. Terapkan rotasi kompensasi apabila pengguna memutar kamera manual
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
      debugPrint('⚠️ [GuidedCamera] Gagal memproses rotasi gambar: $e');
      return imagePath;
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    _pulseController.dispose();
    super.dispose();
  }

  /// Reliably detect faces by taking a snapshot every 750ms
  /// and running ML Kit on the upright-baked file.
  void _startPeriodicDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 750), (_) async {
      final ctrl = _controller;
      if (_isDetecting ||
          _isCapturing ||
          _isSwitchingCamera ||
          ctrl == null ||
          !ctrl.value.isInitialized) {
        return;
      }
      _isDetecting = true;

      try {
        final XFile xFile = await ctrl.takePicture();
        // Jika pengguna melakukan rotasi manual, putar file sementara sebelum deteksi ML Kit
        if (_manualRotationQuarterTurns != 0) {
          await _ensureImageUpright(xFile.path);
        }
        final inputImage = InputImage.fromFilePath(xFile.path);
        final faces = await _faceDetector.processImage(inputImage);

        try {
          await File(xFile.path).delete();
        } catch (_) {}

        if (mounted && !_isCapturing && !_isSwitchingCamera) {
          setState(() => _isFaceDetected = faces.isNotEmpty);
        }
      } catch (e) {
        debugPrint('Detection tick error: $e');
      }

      _isDetecting = false;
    });
  }

  Future<void> _capturePhoto() async {
    final ctrl = _controller;
    if (_isCapturing ||
        _isSwitchingCamera ||
        ctrl == null ||
        !ctrl.value.isInitialized) {
      return;
    }
    setState(() => _isCapturing = true);

    // Pause periodic detection while capturing
    _detectionTimer?.cancel();

    // Tunggu bila ada tick deteksi yang sedang mengambil gambar agar tidak CameraException
    int waitTicks = 0;
    while (_isDetecting && waitTicks < 12) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitTicks++;
    }

    try {
      final directory = await getTemporaryDirectory();
      final XFile xFile = await ctrl.takePicture();
      final imagePath = join(
        directory.path,
        'reg_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await xFile.saveTo(imagePath);

      // Pastikan citra sudah tegak lurus (EXIF baked + rotasi manual diterapkan)
      await _ensureImageUpright(imagePath);

      // Detect & crop face from the upright photo
      final inputImage = InputImage.fromFilePath(imagePath);
      final cropDetector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
      );
      final faces = await cropDetector.processImage(inputImage);
      await cropDetector.close();

      if (faces.isEmpty) {
        try {
          await File(imagePath).delete();
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Wajah tidak terdeteksi dengan jelas. Pastikan wajah berada di dalam oval dan orientasi kamera tegak lurus.',
              ),
              backgroundColor: AppTheme.error,
              duration: Duration(seconds: 3),
            ),
          );
          setState(() => _isCapturing = false);
          _startPeriodicDetection();
        }
        return;
      }

      String finalPath = imagePath;
      final bb = faces.first.boundingBox;
      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage != null) {
        // Square head-centered crop dengan margin 1.55x (anti-potong dahi & rambut)
        final double cx = bb.left + bb.width / 2.0;
        final double cy = bb.top + bb.height * 0.40;

        final double maxSide = bb.width > bb.height ? bb.width : bb.height;
        final int side =
            (maxSide * 1.55).round().clamp(140, originalImage.height);

        int x1 = (cx - side / 2.0).round();
        int y1 = (cy - side / 2.0).round();
        int x2 = x1 + side;
        int y2 = y1 + side;

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

        final cropped = img.copyCrop(
          originalImage,
          x: x1,
          y: y1,
          width: width,
          height: height,
        );
        final croppedPath = join(
          directory.path,
          'crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        File(croppedPath).writeAsBytesSync(img.encodeJpg(cropped, quality: 95));
        finalPath = croppedPath;
      }

      _capturedPhotos.add(File(finalPath));

      if (_currentPoseIndex < 4) {
        setState(() {
          _currentPoseIndex++;
          _isFaceDetected = false;
          _isCapturing = false;
        });
        _startPeriodicDetection();
      } else {
        if (mounted) Navigator.pop(context, _capturedPhotos);
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil foto: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _isCapturing = false);
        _startPeriodicDetection();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final pose = _poses[_currentPoseIndex];
    final isReady =
        _controller != null && _controller!.value.isInitialized && !_isSwitchingCamera;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Registrasi Wajah',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          // Tombol Ganti Kamera Depan / Belakang
          IconButton(
            tooltip: _currentCamera.lensDirection == CameraLensDirection.front
                ? 'Ganti ke Kamera Belakang'
                : 'Ganti ke Kamera Depan',
            onPressed: _switchCameraLens,
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cameraswitch_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          // Tombol Putar Orientasi Kamera 90° (untuk Tablet Landscape / Portrait)
          IconButton(
            tooltip: 'Putar Orientasi Kamera 90°',
            onPressed: _toggleCameraRotation,
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rotate_90_degrees_cw_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          // Tombol Refresh Kamera
          IconButton(
            tooltip: 'Muat Ulang Kamera',
            onPressed: _refreshCamera,
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundDark, // #0F172A
              AppTheme.surfaceDark,    // #1E293B
            ],
          ),
        ),
        child: SafeArea(
          child: !isReady
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primary),
                      const SizedBox(height: 14),
                      Text(
                        _isSwitchingCamera
                            ? 'Mengalihkan kamera...'
                            : 'Menyiapkan kamera registrasi...',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : OrientationBuilder(
                  builder: (context, orientation) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isLandscape =
                            orientation == Orientation.landscape ||
                                constraints.maxWidth > 700;

                        if (isLandscape) {
                          return _buildLandscapeLayout(pose, constraints);
                        }
                        return _buildPortraitLayout(pose, constraints);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PORTRAIT LAYOUT — Header(Progress) → Camera(Expanded) → Footer(Card+Btn)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPortraitLayout(
    Map<String, dynamic> pose,
    BoxConstraints constraints,
  ) {
    return Column(
      children: [
        const SizedBox(height: 8),

        // ── Segmented Progress Bar ──
        _buildSegmentedProgressBar(),

        const SizedBox(height: 6),

        Text(
          'Foto ${_currentPoseIndex + 1} dari 5',
          style: const TextStyle(
            color: Color(0x73FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 12),

        // ── Camera Preview ──
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildCameraContainer(),
            ),
          ),
        ),

        // ── Bottom: Instruction Card + Capture Button ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInstructionCard(pose),
              const SizedBox(height: 16),
              _buildCaptureButton(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LANDSCAPE LAYOUT — Left(Progress, Instructions, Button) → Right(Camera)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLandscapeLayout(
    Map<String, dynamic> pose,
    BoxConstraints constraints,
  ) {
    return Row(
      children: [
        // ── Left Pane: Controls ──
        Expanded(
          flex: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSegmentedProgressBar(),

                  const SizedBox(height: 8),

                  Text(
                    'Foto ${_currentPoseIndex + 1} dari 5',
                    style: const TextStyle(
                      color: Color(0x73FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildInstructionCard(pose),

                  const SizedBox(height: 22),

                  _buildCaptureButton(),
                ],
              ),
            ),
          ),
        ),

        // ── Right Pane: Camera ──
        Expanded(
          flex: 58,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 24, 12),
            child: Center(child: _buildCameraContainer()),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Segmented progress bar — 5 equal line segments with glow on active
  Widget _buildSegmentedProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: List.generate(5, (index) {
          final isComplete = index < _currentPoseIndex;
          final isCurrent = index == _currentPoseIndex;

          Color segmentColor;
          List<BoxShadow>? glow;

          if (isComplete) {
            segmentColor = AppTheme.success;
            glow = null;
          } else if (isCurrent) {
            segmentColor = AppTheme.primary;
            glow = [
              const BoxShadow(
                color: Color(0x802563EB),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ];
          } else {
            segmentColor = const Color(0x1FFFFFFF);
            glow = null;
          }

          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              height: 4,
              margin: EdgeInsets.only(right: index < 4 ? 6 : 0),
              decoration: BoxDecoration(
                color: segmentColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: glow,
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Undistorted & Rotation-Aware Camera Feed (matching PresensiView)
  Widget _buildCameraFeed() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox();
    }

    final int quarterTurns = _getDisplayRotationQuarterTurns();
    final double rawAr = ctrl.value.aspectRatio;
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
                child: CameraPreview(ctrl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Camera preview with ClipRRect(32), oval overlay, detection chip, and active lens pill
  Widget _buildCameraContainer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: AspectRatio(
        aspectRatio: 3 / 4, // portrait 3:4 card
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Undistorted & Rotated Camera Feed
            _buildCameraFeed(),

            // 2. Oval overlay with pulse animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _FaceOvalPainter(
                    isFaceDetected: _isFaceDetected,
                    pulseValue: _isFaceDetected ? 0.0 : _pulseController.value,
                  ),
                );
              },
            ),

            // 3. Face status chip — top center
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _isFaceDetected
                        ? const Color(0xE610B981)
                        : const Color(0xCC334155),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isFaceDetected
                          ? const Color(0x4D10B981)
                          : const Color(0x14FFFFFF),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFaceDetected
                            ? Icons.check_circle_rounded
                            : Icons.face,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isFaceDetected
                            ? 'Wajah Terdeteksi'
                            : 'Mencari wajah...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Active Camera & Rotation Indicator — bottom center inside card
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xB30F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentCamera.lensDirection ==
                                CameraLensDirection.front
                            ? Icons.camera_front_rounded
                            : Icons.camera_rear_rounded,
                        color: const Color(0xFF60A5FA),
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currentCamera.lensDirection ==
                                CameraLensDirection.front
                            ? 'Kamera Depan'
                            : 'Kamera Belakang',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_manualRotationQuarterTurns != 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• ${_manualRotationQuarterTurns * 90}°',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Instruction card — glassmorphic pill with icon + pose label
  Widget _buildInstructionCard(Map<String, dynamic> pose) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
                  .animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey<int>(_currentPoseIndex),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x14FFFFFF), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x262563EB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                pose['icon'] as IconData,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_currentPoseIndex + 1}. ${pose['label']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pose['desc'] as String,
                    style: const TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern floating capture button with soft blue shadow
  Widget _buildCaptureButton() {
    final isReady = _isFaceDetected && !_isCapturing && !_isSwitchingCamera;

    return GestureDetector(
      onTap: isReady ? _capturePhoto : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isCapturing
              ? const Color(0xFF334155)
              : isReady
                  ? Colors.white
                  : const Color(0x14FFFFFF),
          border: Border.all(
            color: isReady ? AppTheme.primary : const Color(0x26FFFFFF),
            width: isReady ? 3.5 : 2.5,
          ),
          boxShadow: isReady
              ? [
                  const BoxShadow(
                    color: Color(0x592563EB),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: _isCapturing
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppTheme.primary,
                ),
              )
            : Icon(
                Icons.camera_alt_rounded,
                size: 30,
                color: isReady ? AppTheme.primary : const Color(0x33FFFFFF),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FACE OVAL OVERLAY — Refined for design system
// ═══════════════════════════════════════════════════════════════════════════════

class _FaceOvalPainter extends CustomPainter {
  final bool isFaceDetected;
  final double pulseValue;

  _FaceOvalPainter({required this.isFaceDetected, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final ovalWidth = size.width * 0.60;
    final ovalHeight = ovalWidth * 1.35;
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // Dark overlay with oval cutout
    final overlayPaint = Paint()..color = const Color(0x80000000);
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, overlayPaint);

    // Oval border — success green when detected, primary blue pulse otherwise
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isFaceDetected ? 3.0 : 2.5 + (pulseValue * 1.0)
      ..color = isFaceDetected
          ? const Color(0xFF10B981)
          : Color.lerp(
              const Color(0x592563EB),
              const Color(0xD92563EB),
              pulseValue,
            )!;
    canvas.drawOval(ovalRect, borderPaint);

    // Corner markers when face detected
    if (isFaceDetected) {
      final mp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF10B981);

      const len = 18.0;
      // Top-left
      canvas.drawLine(
        Offset(ovalRect.left + 8, ovalRect.top),
        Offset(ovalRect.left + 8 + len, ovalRect.top),
        mp,
      );
      canvas.drawLine(
        Offset(ovalRect.left, ovalRect.top + 8),
        Offset(ovalRect.left, ovalRect.top + 8 + len),
        mp,
      );
      // Top-right
      canvas.drawLine(
        Offset(ovalRect.right - 8, ovalRect.top),
        Offset(ovalRect.right - 8 - len, ovalRect.top),
        mp,
      );
      canvas.drawLine(
        Offset(ovalRect.right, ovalRect.top + 8),
        Offset(ovalRect.right, ovalRect.top + 8 + len),
        mp,
      );
      // Bottom-left
      canvas.drawLine(
        Offset(ovalRect.left + 8, ovalRect.bottom),
        Offset(ovalRect.left + 8 + len, ovalRect.bottom),
        mp,
      );
      canvas.drawLine(
        Offset(ovalRect.left, ovalRect.bottom - 8),
        Offset(ovalRect.left, ovalRect.bottom - 8 - len),
        mp,
      );
      // Bottom-right
      canvas.drawLine(
        Offset(ovalRect.right - 8, ovalRect.bottom),
        Offset(ovalRect.right - 8 - len, ovalRect.bottom),
        mp,
      );
      canvas.drawLine(
        Offset(ovalRect.right, ovalRect.bottom - 8),
        Offset(ovalRect.right, ovalRect.bottom - 8 - len),
        mp,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter old) =>
      old.isFaceDetected != isFaceDetected || old.pulseValue != pulseValue;
}
