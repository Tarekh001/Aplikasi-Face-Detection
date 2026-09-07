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
class GuidedCameraPage extends StatefulWidget {
  final CameraDescription camera;
  final int startFromIndex;

  const GuidedCameraPage({
    required this.camera,
    this.startFromIndex = 0,
    super.key,
  });

  @override
  State<GuidedCameraPage> createState() => _GuidedCameraPageState();
}

class _GuidedCameraPageState extends State<GuidedCameraPage>
    with SingleTickerProviderStateMixin {
  late CameraController _controller;
  late Future<void> _initFuture;
  late FaceDetector _faceDetector;
  late AnimationController _pulseController;
  Timer? _detectionTimer;

  final List<File> _capturedPhotos = [];
  int _currentPoseIndex = 0;
  bool _isFaceDetected = false;
  bool _isCapturing = false;
  bool _isDetecting = false;

  // ── Pose data — clean, NO emojis, punchy human-readable instructions ──
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

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initFuture = _controller.initialize().then((_) {
      if (mounted) _startPeriodicDetection();
    });

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _controller.dispose();
    _faceDetector.close();
    _pulseController.dispose();
    super.dispose();
  }

  /// Reliably detect faces by taking a snapshot every 700ms
  /// and running ML Kit on the saved file (handles rotation/format automatically).
  void _startPeriodicDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      if (_isDetecting || _isCapturing || !_controller.value.isInitialized) return;
      _isDetecting = true;

      try {
        final XFile xFile = await _controller.takePicture();
        final inputImage = InputImage.fromFilePath(xFile.path);
        final faces = await _faceDetector.processImage(inputImage);

        // Cleanup temp file
        try { await File(xFile.path).delete(); } catch (_) {}

        if (mounted) {
          setState(() => _isFaceDetected = faces.isNotEmpty);
        }
      } catch (e) {
        debugPrint('Detection tick error: $e');
      }

      _isDetecting = false;
    });
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || !_controller.value.isInitialized) return;
    setState(() => _isCapturing = true);

    // Pause detection while capturing
    _detectionTimer?.cancel();

    try {
      final directory = await getTemporaryDirectory();
      final XFile xFile = await _controller.takePicture();
      final imagePath = join(directory.path, 'reg_${DateTime.now().millisecondsSinceEpoch}.png');
      await xFile.saveTo(imagePath);

      // Detect & crop face from the photo
      final inputImage = InputImage.fromFilePath(imagePath);
      final cropDetector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
      );
      final faces = await cropDetector.processImage(inputImage);
      cropDetector.close();

      String finalPath = imagePath;

      if (faces.isNotEmpty) {
        final bb = faces.first.boundingBox;
        final bytes = await File(imagePath).readAsBytes();
        final originalImage = img.decodeImage(bytes);

        if (originalImage != null) {
          final padW = (bb.width * 0.20).toInt();
          final padH = (bb.height * 0.20).toInt();
          final x = (bb.left.toInt() - padW).clamp(0, originalImage.width - 1);
          final y = (bb.top.toInt() - padH).clamp(0, originalImage.height - 1);
          final w = (bb.width.toInt() + padW * 2).clamp(1, originalImage.width - x);
          final h = (bb.height.toInt() + padH * 2).clamp(1, originalImage.height - y);

          final cropped = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
          final croppedPath = join(directory.path, 'crop_${DateTime.now().millisecondsSinceEpoch}.png');
          File(croppedPath).writeAsBytesSync(img.encodePng(cropped));
          finalPath = croppedPath;
        }
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
          SnackBar(content: Text('Gagal mengambil foto: $e'), backgroundColor: AppTheme.error),
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Registrasi Wajah',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.3),
        ),
        centerTitle: true,
        elevation: 0,
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
          child: FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                );
              }

              return OrientationBuilder(
                builder: (context, orientation) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape = orientation == Orientation.landscape ||
                          constraints.maxWidth > 700;

                      if (isLandscape) {
                        return _buildLandscapeLayout(pose, constraints);
                      }
                      return _buildPortraitLayout(pose, constraints);
                    },
                  );
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

  Widget _buildPortraitLayout(Map<String, dynamic> pose, BoxConstraints constraints) {
    return Column(
      children: [
        const SizedBox(height: 8),

        // ── Segmented Progress Bar ──
        _buildSegmentedProgressBar(),

        const SizedBox(height: 6),

        Text(
          'Foto ${_currentPoseIndex + 1} dari 5',
          style: const TextStyle(
            color: Color(0x73FFFFFF), // white 45%
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 16),

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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInstructionCard(pose),
              const SizedBox(height: 20),
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

  Widget _buildLandscapeLayout(Map<String, dynamic> pose, BoxConstraints constraints) {
    return Row(
      children: [
        // ── Left Pane: Controls ──
        Expanded(
          flex: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 1),

                _buildSegmentedProgressBar(),

                const SizedBox(height: 8),

                Text(
                  'Foto ${_currentPoseIndex + 1} dari 5',
                  style: const TextStyle(
                    color: Color(0x73FFFFFF), // white 45%
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 24),

                _buildInstructionCard(pose),

                const SizedBox(height: 28),

                _buildCaptureButton(),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ),

        // ── Right Pane: Camera ──
        Expanded(
          flex: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 24, 12),
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
              BoxShadow(
                color: const Color(0x802563EB), // primary 50%
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ];
          } else {
            segmentColor = const Color(0x1FFFFFFF); // white 12%
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

  /// Camera preview with ClipRRect(32), oval overlay, and detection chip
  Widget _buildCameraContainer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: AspectRatio(
        aspectRatio: 3 / 4, // portrait 3:4
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.previewSize?.height ?? 480,
                height: _controller.value.previewSize?.width ?? 640,
                child: CameraPreview(_controller),
              ),
            ),

            // Oval overlay with pulse animation
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

            // Face status chip — top center
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _isFaceDetected
                        ? const Color(0xE610B981) // success 90%
                        : const Color(0xCC334155), // slate700 80%
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isFaceDetected
                          ? const Color(0x4D10B981) // success 30%
                          : const Color(0x14FFFFFF), // white 8%
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFaceDetected ? Icons.check_circle_rounded : Icons.face,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isFaceDetected ? 'Wajah Terdeteksi' : 'Mencari wajah...',
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
          position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey<int>(_currentPoseIndex),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF), // white 7%
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x14FFFFFF), width: 1), // white 8%
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pose icon in a rounded square
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x262563EB), // primary 15%
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                pose['icon'] as IconData,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // Text
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
                      color: Color(0x80FFFFFF), // white 50%
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
    final isReady = _isFaceDetected && !_isCapturing;

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
                  : const Color(0x14FFFFFF), // white 8%
          border: Border.all(
            color: isReady
                ? AppTheme.primary
                : const Color(0x26FFFFFF), // white 15%
            width: isReady ? 3.5 : 2.5,
          ),
          boxShadow: isReady
              ? [
                  const BoxShadow(
                    color: Color(0x592563EB), // primary 35%
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
                color: isReady ? AppTheme.primary : const Color(0x33FFFFFF), // white 20%
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FACE OVAL OVERLAY — Refined for design system
// ═══════════════════════════════════════════════════════════════════════════════

/// Oval overlay painter with animated border, aligned to AppTheme colors.
class _FaceOvalPainter extends CustomPainter {
  final bool isFaceDetected;
  final double pulseValue;

  _FaceOvalPainter({required this.isFaceDetected, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final ovalWidth = size.width * 0.60;
    final ovalHeight = ovalWidth * 1.35;
    final ovalRect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

    // Dark overlay with oval cutout
    final overlayPaint = Paint()..color = const Color(0x80000000); // black 50%
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
          ? const Color(0xFF10B981) // AppTheme.success
          : Color.lerp(
              const Color(0x592563EB), // primary 35%
              const Color(0xD92563EB), // primary 85%
              pulseValue,
            )!;
    canvas.drawOval(ovalRect, borderPaint);

    // Corner markers when face detected
    if (isFaceDetected) {
      final mp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF10B981); // AppTheme.success

      const len = 18.0;
      // Top-left
      canvas.drawLine(Offset(ovalRect.left + 8, ovalRect.top), Offset(ovalRect.left + 8 + len, ovalRect.top), mp);
      canvas.drawLine(Offset(ovalRect.left, ovalRect.top + 8), Offset(ovalRect.left, ovalRect.top + 8 + len), mp);
      // Top-right
      canvas.drawLine(Offset(ovalRect.right - 8, ovalRect.top), Offset(ovalRect.right - 8 - len, ovalRect.top), mp);
      canvas.drawLine(Offset(ovalRect.right, ovalRect.top + 8), Offset(ovalRect.right, ovalRect.top + 8 + len), mp);
      // Bottom-left
      canvas.drawLine(Offset(ovalRect.left + 8, ovalRect.bottom), Offset(ovalRect.left + 8 + len, ovalRect.bottom), mp);
      canvas.drawLine(Offset(ovalRect.left, ovalRect.bottom - 8), Offset(ovalRect.left, ovalRect.bottom - 8 - len), mp);
      // Bottom-right
      canvas.drawLine(Offset(ovalRect.right - 8, ovalRect.bottom), Offset(ovalRect.right - 8 - len, ovalRect.bottom), mp);
      canvas.drawLine(Offset(ovalRect.right, ovalRect.bottom - 8), Offset(ovalRect.right, ovalRect.bottom - 8 - len), mp);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter old) =>
      old.isFaceDetected != isFaceDetected || old.pulseValue != pulseValue;
}
