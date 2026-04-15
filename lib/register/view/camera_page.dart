import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

class CameraPage extends StatefulWidget {
  final CameraDescription camera;

  const CameraPage({required this.camera, super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String?> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final directory = await getTemporaryDirectory();
      final imagePath = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.png');

      final XFile file = await _controller.takePicture();
      await file.saveTo(imagePath);

      final inputImage = InputImage.fromFilePath(imagePath);

      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
      );

      final faceDetector = FaceDetector(options: options);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('No face detected — returning full image');
        return imagePath;
      }

      final face = faces.first;
      final boundingBox = face.boundingBox;

      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        debugPrint('Failed to decode image');
        return null;
      }

      final x = boundingBox.left.toInt().clamp(0, originalImage.width - 1);
      final y = boundingBox.top.toInt().clamp(0, originalImage.height - 1);
      final width = boundingBox.width.toInt().clamp(1, originalImage.width - x);
      final height = boundingBox.height.toInt().clamp(1, originalImage.height - y);

      final cropped = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);

      final croppedPath = join(directory.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.png');
      File(croppedPath).writeAsBytesSync(img.encodePng(cropped));

      return croppedPath;
    } catch (e) {
      debugPrint('Error taking picture and cropping: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ambil Foto')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return CameraPreview(_controller);
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100.0),
        child: FloatingActionButton(
          onPressed: () async {
            final path = await _takePicture();
            if (path != null) {
              Navigator.pop(context, File(path));
            }
          },
          child: const Icon(
            Icons.camera,
            size: 36.0,
          ),
        ),
      ),
    );
  }
}
