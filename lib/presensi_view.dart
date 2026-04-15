import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

import 'services/api_service.dart';

import 'models/api_error.dart';
import 'hasil_view.dart';

class PresensiView extends StatefulWidget {
  const PresensiView({super.key});

  @override
  State<PresensiView> createState() => _PresensiViewState();
}

class _PresensiViewState extends State<PresensiView> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isDetecting = false;
  String _detectionText = "Arahkan wajah ke kamera";
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  bool _hasBlinked = false;
  bool _hasTurnedHead = false;
  bool _isUploading = false;
  bool _isCountingDown = false;
  int _countdownValue = 3;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _errorResetTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception("Tidak ada kamera yang tersedia");
      }

      final CameraDescription camera = _cameras.firstWhere(
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

      setState(() {});
      _startFaceDetection();
    } catch (e) {
      debugPrint("⚠️ Error in _initializeCamera: $e");
      setState(() {
        _detectionText = "Kamera tidak dapat diinisialisasi ❌";
      });
    }
  }

  InputImageRotation _rotationFromSensorOrientation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || _isCountingDown || _isUploading) return;
      _isDetecting = true;

      try {
        final faces = await _detectFaces(image);

        if (faces.isNotEmpty) {
          _validateLiveness(faces);
        } else {
          if (mounted) {
            setState(() => _detectionText = "Tidak Ada Wajah ❌");
          }
        }
      } catch (e) {
        debugPrint("⚠️ Error Face Detection: $e");
      }

      _isDetecting = false;
    });
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

    // Copy Y
    int index = 0;
    for (int row = 0; row < height; row++) {
      final int rowOffset = row * planeY.bytesPerRow;
      nv21Image.setRange(index, index + width, planeY.bytes, rowOffset);
      index += width;
    }

    // Copy interleaved VU
    final int chromaRowStride = planeU.bytesPerRow;
    final int chromaPixelStride = planeU.bytesPerPixel!;

    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int uvOffset = row * chromaRowStride + col * chromaPixelStride;
        nv21Image[index++] = planeV.bytes[uvOffset]; // V
        nv21Image[index++] = planeU.bytes[uvOffset]; // U
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

  void _validateLiveness(List<Face> faces) async {
    final face = faces.first;

    double? leftEye = face.leftEyeOpenProbability;
    double? rightEye = face.rightEyeOpenProbability;
    double headTurn = face.headEulerAngleY ?? 0;

    if (leftEye != null && rightEye != null) {
      if (leftEye < 0.3 && rightEye < 0.3) {
        _hasBlinked = true;
      }
    }

    if (headTurn > 15 || headTurn < -15) {
      _hasTurnedHead = true;
    }

    if (_hasBlinked && _hasTurnedHead) {
      // Liveness verified → start countdown
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
      if (mounted) {
        setState(() => _detectionText = hint);
      }
    }
  }

  /// Step 7: Countdown 3-2-1 before capture
  void _startCountdown() async {
    if (_isCountingDown) return;

    setState(() {
      _isCountingDown = true;
      _countdownValue = 3;
      _detectionText = "Liveness Verified ✅";
    });

    // Stop image stream during countdown
    await _cameraController!.stopImageStream();

    for (int i = 3; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdownValue = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() => _isCountingDown = false);

    // Capture and upload
    await _captureAndUpload();
  }

  /// Captures photo, crops face, and uploads via ApiService
  Future<void> _captureAndUpload() async {
    setState(() {
      _isUploading = true;
      _detectionText = "⏳ Memproses foto...";
    });

    try {
      final croppedPath = await _takeAndCropFacePicture();
      if (croppedPath != null) {
        final croppedFile = File(croppedPath);
        await _uploadPhoto(croppedFile);
      } else {
        _showError("Gagal memproses foto wajah");
      }
    } catch (e) {
      debugPrint("❌ Gagal capture/upload: $e");
      _showError("Gagal memproses foto: ${e.toString().split('\n').first}");
    }
  }

  /// Uploads the cropped face photo using the centralized ApiService.
  Future<void> _uploadPhoto(File photoFile) async {
    setState(() {
      _detectionText = "⏳ Mengunggah foto...";
    });

    try {
      final result = await ApiService.predictFace(photoFile);

      if (!mounted) return;

      // Success! Navigate to result screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HasilView(
            name: result.name,
            waktu: result.waktu,
            status: result.status,
          ),
        ),
      );
    } on ApiError catch (e) {
      debugPrint("❌ API Error: $e");
      _showError(e.error);
    } catch (e) {
      debugPrint("❌ Upload error: $e");
      _showError("Upload gagal: ${e.toString().split('\n').first}");
    }
  }

  /// Shows error overlay with auto-reset after 5 seconds
  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _hasError = true;
      _errorMessage = message;
      _isUploading = false;
    });

    // Auto-reset after 5 seconds
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(seconds: 5), () {
      _resetState();
    });
  }

  /// Resets everything to initial state — ready for next person
  void _resetState() {
    if (!mounted) return;

    _errorResetTimer?.cancel();

    setState(() {
      _hasBlinked = false;
      _hasTurnedHead = false;
      _isDetecting = false;
      _isUploading = false;
      _isCountingDown = false;
      _hasError = false;
      _errorMessage = '';
      _detectionText = "Arahkan wajah ke kamera";
    });

    // Restart camera stream
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        _startFaceDetection();
      } catch (e) {
        debugPrint("⚠️ Error restarting face detection: $e");
      }
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
        enableContours: false,
        enableLandmarks: false,
      );

      final faceDetector = FaceDetector(options: detectorOptions);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint("⚠️ No face during crop — using full image");
        return imagePath;
      }

      final face = faces.first;
      final boundingBox = face.boundingBox;

      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        debugPrint("❌ Gagal decode gambar untuk cropping.");
        return null;
      }

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

  @override
  void dispose() {
    _errorResetTimer?.cancel();
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _cameraController!.dispose();
    }
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Presensi Wajah"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera preview
                Positioned.fill(
                  child: CameraPreview(_cameraController!),
                ),

                // Face detection guide overlay (oval frame)
                Center(
                  child: Container(
                    width: 260,
                    height: 340,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _hasBlinked && _hasTurnedHead
                            ? Colors.green
                            : Colors.white.withValues(alpha: 0.6),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(130),
                    ),
                  ),
                ),

                // Liveness checklist
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _hasBlinked ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: _hasBlinked ? Colors.greenAccent : Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Kedip',
                          style: TextStyle(
                            color: _hasBlinked ? Colors.greenAccent : Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Icon(
                          _hasTurnedHead ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: _hasTurnedHead ? Colors.greenAccent : Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Putar Kepala',
                          style: TextStyle(
                            color: _hasTurnedHead ? Colors.greenAccent : Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Detection status text
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _detectionText,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),

                // Step 7: Countdown overlay
                if (_isCountingDown)
                  Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Tetap diam...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TweenAnimationBuilder<double>(
                            key: ValueKey(_countdownValue),
                            tween: Tween(begin: 1.5, end: 1.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: Text(
                                  '$_countdownValue',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 100,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // Upload loading overlay
                if (_isUploading && !_hasError)
                  Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 20),
                          Text(
                            "Mengunggah & memproses...",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Step 9: Error overlay with retry
                if (_hasError)
                  Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 72),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _resetState,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Coba Lagi', style: TextStyle(fontSize: 16)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Otomatis reset dalam 5 detik...',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
