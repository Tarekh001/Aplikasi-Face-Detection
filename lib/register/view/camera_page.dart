// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:path/path.dart' show join;
// import 'package:path_provider/path_provider.dart';
//
// class CameraPage extends StatefulWidget {
//   final CameraDescription camera;
//
//   const CameraPage({required this.camera, super.key});
//
//   @override
//   State<CameraPage> createState() => _CameraPageState();
// }
//
// class _CameraPageState extends State<CameraPage> {
//   late CameraController _controller;
//   late Future<void> _initializeControllerFuture;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller = CameraController(widget.camera, ResolutionPreset.medium);
//     _initializeControllerFuture = _controller.initialize();
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
//
//   Future<String?> _takePicture() async {
//     try {
//       await _initializeControllerFuture;
//       final directory = await getTemporaryDirectory();
//       final path = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.png');
//       final XFile file = await _controller.takePicture();
//       await file.saveTo(path);
//       return path;
//     } catch (e) {
//       print('Error taking picture: $e');
//       return null;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Ambil Foto')),
//       body: FutureBuilder<void>(
//         future: _initializeControllerFuture,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState != ConnectionState.done) {
//             return const Center(child: CircularProgressIndicator());
//           }
//           return CameraPreview(_controller);
//         },
//       ),
//       floatingActionButton: Padding(
//         padding: const EdgeInsets.only(bottom: 100.0),
//         child: FloatingActionButton(
//           onPressed: () async {
//             final path = await _takePicture();
//             if (path != null) {
//               Navigator.pop(context, File(path));
//             }
//           },
//           child: const Icon(
//             Icons.camera,
//             size: 36.0,
//           ),
//         ),
//       ),
//     );
//   }
// }


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

      // Ambil gambar dari kamera
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
        print('No face detected');
        return imagePath; // fallback: return original
      }

      // Ambil wajah pertama
      final face = faces.first;
      final boundingBox = face.boundingBox;

      // Baca dan decode gambar
      final bytes = await File(imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        print('Gagal decode image');
        return null;
      }

      // Sesuaikan bounding box jika out of range
      final x = boundingBox.left.toInt().clamp(0, originalImage.width - 1);
      final y = boundingBox.top.toInt().clamp(0, originalImage.height - 1);
      final width = boundingBox.width.toInt().clamp(1, originalImage.width - x);
      final height = boundingBox.height.toInt().clamp(1, originalImage.height - y);

      final cropped = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);

      // Simpan hasil crop
      final croppedPath = join(directory.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.png');
      final croppedFile = File(croppedPath)..writeAsBytesSync(img.encodePng(cropped));

      return croppedFile.path;
    } catch (e) {
      print('Error taking picture and cropping: $e');
      return null;
    }
  }


  // Future<String?> _takePicture() async {
  //   try {
  //     await _initializeControllerFuture;
  //     final directory = await getTemporaryDirectory();
  //     final imagePath = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.png');
  //
  //     final XFile file = await _controller.takePicture();
  //     await file.saveTo(imagePath);
  //
  //     final inputImage = InputImage.fromFilePath(imagePath);
  //
  //     final faceDetector = FaceDetector(
  //       options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  //     );
  //
  //     final faces = await faceDetector.processImage(inputImage);
  //     if (faces.isEmpty) {
  //       print("No face found");
  //       return imagePath;
  //     }
  //
  //     final boundingBox = faces.first.boundingBox;
  //     final bytes = await File(imagePath).readAsBytes();
  //     final originalImage = img.decodeImage(bytes);
  //     if (originalImage == null) return null;
  //
  //     final x = boundingBox.left.toInt().clamp(0, originalImage.width);
  //     final y = boundingBox.top.toInt().clamp(0, originalImage.height);
  //     final w = boundingBox.width.toInt().clamp(0, originalImage.width - x);
  //     final h = boundingBox.height.toInt().clamp(0, originalImage.height - y);
  //
  //     final faceImage = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
  //     final ovalFace = _cropOval(faceImage);
  //
  //     final outputPath = join(directory.path, 'oval_face_${DateTime.now().millisecondsSinceEpoch}.png');
  //     await File(outputPath).writeAsBytes(img.encodePng(ovalFace));
  //
  //     return outputPath;
  //   } catch (e) {
  //     print("Error: $e");
  //     return null;
  //   }
  // }
  //
  // img.Image _cropOval(img.Image src) {
  //   // Buat output image dengan transparansi (RGBA / 4 channel)
  //   final output = img.Image(width: src.width, height: src.height, numChannels: 4);
  //
  //   // Set semua pixel jadi transparan
  //  // output.fill(0x00000000); // transparan
  //
  //   final centerX = src.width / 2;
  //   final centerY = src.height / 2;
  //   final radiusX = src.width / 2;
  //   final radiusY = src.height / 2;
  //
  //   for (int y = 0; y < src.height; y++) {
  //     for (int x = 0; x < src.width; x++) {
  //       final dx = (x - centerX) / radiusX;
  //       final dy = (y - centerY) / radiusY;
  //       if (dx * dx + dy * dy <= 1) {
  //         final pixel = src.getPixel(x, y);
  //         output.setPixel(x, y, pixel);
  //       }
  //     }
  //   }
  //
  //   return output;
  // }
  //



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
