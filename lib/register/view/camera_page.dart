import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

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

  static const List<Map<String, dynamic>> _poses = [
    {'label': 'Wajah Lurus & Netral', 'icon': '😐', 'desc': 'Pandang kamera dengan ekspresi netral'},
    {'label': 'Wajah Tersenyum', 'icon': '😊', 'desc': 'Tersenyum natural ke kamera'},
    {'label': 'Menoleh Kanan', 'icon': '👉', 'desc': 'Toleh sedikit ke kanan Anda'},
    {'label': 'Menoleh Kiri', 'icon': '👈', 'desc': 'Toleh sedikit ke kiri Anda'},
    {'label': 'Sedikit Mendongak', 'icon': '🔼', 'desc': 'Angkat dagu sedikit ke atas'},
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
        debugPrint('⚠️ Detection tick error: $e');
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
      debugPrint('❌ Error capturing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isCapturing = false);
        _startPeriodicDetection();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pose = _poses[_currentPoseIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Registrasi Wajah', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          return Column(
            children: [
              const SizedBox(height: 8),

              // ── Progress Dots ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final isComplete = index < _currentPoseIndex;
                  final isCurrent = index == _currentPoseIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: isCurrent ? 34 : 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isComplete
                          ? Colors.greenAccent
                          : isCurrent
                              ? Colors.amberAccent
                              : Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 6),

              Text(
                'Foto ${_currentPoseIndex + 1} dari 5',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),

              const SizedBox(height: 16),

              // ── Camera Preview (4:3 aspect) ──
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 3 / 4, // portrait 4:3
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

                            // Oval overlay
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

                            // Face status indicator top-center
                            Positioned(
                              top: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _isFaceDetected
                                        ? Colors.green.withOpacity(0.85)
                                        : Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isFaceDetected ? Icons.face_retouching_natural : Icons.face,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isFaceDetected ? 'Wajah Terdeteksi' : 'Mencari wajah...',
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
                  ),
                ),
              ),

              // ── Bottom: Pose instruction + Capture ──
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pose info with animation
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
                              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey<int>(_currentPoseIndex),
                        children: [
                          Text(pose['icon'], style: const TextStyle(fontSize: 40)),
                          const SizedBox(height: 4),
                          Text(
                            pose['label'],
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(pose['desc'], style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Capture button
                    GestureDetector(
                      onTap: (_isFaceDetected && !_isCapturing) ? _capturePhoto : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isFaceDetected ? Colors.greenAccent : Colors.white30,
                            width: 4,
                          ),
                          color: _isCapturing
                              ? Colors.grey
                              : _isFaceDetected
                                  ? Colors.white
                                  : Colors.white12,
                          boxShadow: _isFaceDetected
                              ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]
                              : [],
                        ),
                        child: _isCapturing
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple),
                              )
                            : Icon(
                                Icons.camera_alt_rounded,
                                size: 32,
                                color: _isFaceDetected ? Colors.deepPurple : Colors.white30,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Oval overlay painter with animated border
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
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, overlayPaint);

    // Oval border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isFaceDetected ? 3.5 : 2.5 + (pulseValue * 1.0)
      ..color = isFaceDetected
          ? Colors.greenAccent
          : Colors.amberAccent.withOpacity(0.5 + pulseValue * 0.5);
    canvas.drawOval(ovalRect, borderPaint);

    // Corner markers when face detected
    if (isFaceDetected) {
      final mp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Colors.greenAccent;

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
