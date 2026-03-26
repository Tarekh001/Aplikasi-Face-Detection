//
//
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:dio/dio.dart';
// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;
// import 'package:path/path.dart';
// import 'package:path_provider/path_provider.dart';
//
// import 'hasil_view.dart';
//
// class PresensiView extends StatefulWidget {
//   @override
//   _PresensiViewState createState() => _PresensiViewState();
// }
//
// class _PresensiViewState extends State<PresensiView> {
//   CameraController? _cameraController;
//   late List<CameraDescription> _cameras;
//   bool _isDetecting = false;
//   String _detectionText = "Mendeteksi...";
//   final FaceDetector _faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       performanceMode: FaceDetectorMode.accurate,
//     ),
//   );
//
//   bool hasBlinked = false;
//   bool hasTurnedHead = false;
//
//   bool isNavigation = false;
//   String? nik, nama;
//   bool _isUploading = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeCamera();
//   }
//
//   Future<void> _initializeCamera() async {
//     try {
//       _cameras = await availableCameras();
//       if (_cameras.isEmpty) {
//         throw Exception("Tidak ada kamera yang tersedia");
//       }
//
//       // Gunakan kamera depan jika ada, jika tidak pakai kamera belakang
//       _cameraController = CameraController(
//         _cameras.length > 1 ? _cameras[1] : _cameras[0],
//         ResolutionPreset.medium,
//       );
//
//       await _cameraController!.initialize();
//       if (!mounted) return;
//
//       setState(() {}); // Refresh UI setelah kamera siap
//       _startFaceDetection();
//     } catch (e) {
//       print("⚠️ Error in _initializeCamera: $e");
//       setState(() {
//         _detectionText = "Kamera tidak dapat diinisialisasi ❌";
//       });
//     }
//   }
//
//   void _startFaceDetection() {
//     if (_cameraController == null || !_cameraController!.value.isInitialized) return;
//
//     _cameraController!.startImageStream((CameraImage image) async {
//       if (_isDetecting) return;
//       _isDetecting = true;
//
//       try {
//         final faces = await _detectFaces(image);
//
//         if (faces.isNotEmpty) {
//           _validateLiveness(faces);
//         } else {
//           setState(() => _detectionText = "Tidak Ada Wajah ❌");
//         }
//       } catch (e) {
//         print("⚠️ Error Face Detection: $e");
//       }
//
//       _isDetecting = false;
//     });
//   }
//
//   Future<void> _uploadPhoto(Uint8List imageBytes) async {
//     setState(() {
//       _isUploading = true;
//       _detectionText = "⏳ Mengunggah foto...";
//     });
//
//     try {
//       final tempDir = await getTemporaryDirectory();
//       final filePath = join(tempDir.path, 'face_${DateTime.now().millisecondsSinceEpoch}.jpg');
//       final file = File(filePath);
//       await file.writeAsBytes(imageBytes);
//
//       final formData = FormData.fromMap({
//         'photo': await MultipartFile.fromFile(file.path, filename: basename(file.path)),
//       });
//
//       final response = await Dio().post(
//         'http://asng-lintas.tangerangkab.my.id/api/predict',
//         data: formData,
//       );
//
//       if (response.statusCode == 200 && response.data is List && response.data.length >= 2) {
//         final nik = response.data[0];
//         final nama = response.data[1];
//         setState(() {
//           _detectionText = "✅ Wajah terdeteksi: $nama";
//           this.nik = nik;
//           this.nama = nama;
//           isNavigation = true;
//         });
//
//         debugPrint("✅ Wajah terdeteksi: $nama");
//       } else {
//         final message = "❌ Format data tidak dikenali dari server.";
//         setState(() => _detectionText = message);
//         debugPrint("$message Respon: ${response.data}");
//       }
//     } catch (e) {
//       final message = "❌ Upload gagal: ${e.toString().split('\n').first}";
//       setState(() => _detectionText = message);
//       debugPrint(message);
//     } finally {
//       setState(() {
//         _isUploading = false;
//       });
//     }
//   }
//
//
//
//
//
//   Future<List<Face>> _detectFaces(CameraImage image) async {
//     final InputImageRotation rotation = InputImageRotation.rotation270deg;
//     final InputImageFormat format = InputImageFormat.nv21;
//     final metadata = InputImageMetadata(
//       size: Size(image.width.toDouble(), image.height.toDouble()),
//       rotation: rotation,
//       format: format,
//       bytesPerRow: image.planes[0].bytesPerRow,
//     );
//
//     final inputImage = InputImage.fromBytes(
//       bytes: _concatenatePlanes(image.planes),
//       metadata: metadata,
//     );
//
//     return await _faceDetector.processImage(inputImage);
//   }
//
//   void _validateLiveness(List<Face> faces) async {
//     final face = faces.first;
//
//     double? leftEye = face.leftEyeOpenProbability;
//     double? rightEye = face.rightEyeOpenProbability;
//     double headTurn = face.headEulerAngleY ?? 0; // Rotasi kepala ke samping
//
//     // Deteksi Kedipan Mata
//     if (leftEye != null && rightEye != null) {
//       if (leftEye < 0.3 && rightEye < 0.3) {
//         hasBlinked = true;
//       }
//     }
//
//     // Deteksi Pergerakan Kepala
//     if (headTurn > 15 || headTurn < -15) {
//       hasTurnedHead = true;
//     }
//
//     // Jika sudah berkedip dan menoleh, berarti orang asli
//     if (hasBlinked && hasTurnedHead) {
//       setState(() => _detectionText = "Liveness Verified ✅");
//
//       await _cameraController!.stopImageStream();
//
//       try {
//         final croppedPath = await _takeAndCropFacePicture();
//         if (croppedPath != null) {
//           final croppedBytes = await File(croppedPath).readAsBytes();
//           await _uploadPhoto(croppedBytes);
//         } else {
//           debugPrint("❌ Gagal cropping wajah.");
//         }
//       } catch (e) {
//         debugPrint("❌ Gagal ambil/crop foto untuk upload: $e");
//       }
//     } else {
//       setState(() => _detectionText = "Lakukan kedipan & putar kepala");
//     }
//   }
//
//   Uint8List _concatenatePlanes(List<Plane> planes) {
//     final BytesBuilder bytesBuilder = BytesBuilder();
//     for (Plane plane in planes) {
//       bytesBuilder.add(plane.bytes);
//     }
//     return bytesBuilder.toBytes();
//   }
//
//   @override
//   void dispose() {
//     if (_cameraController != null && _cameraController!.value.isInitialized) {
//       _cameraController!.dispose();
//     }
//     _faceDetector.close();
//     super.dispose();
//   }
//
//   Future<String?> _takeAndCropFacePicture() async {
//     try {
//       final tempDir = await getTemporaryDirectory();
//       final imagePath = join(tempDir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
//
//       final XFile file = await _cameraController!.takePicture();
//       await file.saveTo(imagePath);
//
//       final inputImage = InputImage.fromFilePath(imagePath);
//       final detectorOptions = FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.accurate,
//         enableContours: false,
//         enableLandmarks: false,
//       );
//
//       final faceDetector = FaceDetector(options: detectorOptions);
//       final faces = await faceDetector.processImage(inputImage);
//
//       if (faces.isEmpty) {
//         debugPrint("❌ Tidak ada wajah terdeteksi saat cropping.");
//         return imagePath; // fallback ke gambar asli
//       }
//
//       final face = faces.first;
//       final boundingBox = face.boundingBox;
//
//       final bytes = await File(imagePath).readAsBytes();
//       final originalImage = img.decodeImage(bytes);
//
//       if (originalImage == null) {
//         debugPrint("❌ Gagal decode gambar untuk cropping.");
//         return null;
//       }
//
//       final x = boundingBox.left.toInt().clamp(0, originalImage.width - 1);
//       final y = boundingBox.top.toInt().clamp(0, originalImage.height - 1);
//       final width = boundingBox.width.toInt().clamp(1, originalImage.width - x);
//       final height = boundingBox.height.toInt().clamp(1, originalImage.height - y);
//
//       final cropped = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
//
//       final croppedPath = join(tempDir.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
//       final croppedFile = File(croppedPath)..writeAsBytesSync(img.encodeJpg(cropped));
//
//       return croppedPath;
//     } catch (e) {
//       debugPrint("❌ Error cropping wajah: $e");
//       return null;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // ✅ Jika isNavigation aktif, pindah halaman (sekali)
//     if (isNavigation && nik != null && nama != null) {
//       // Reset flag supaya tidak loop
//       isNavigation = false;
//
//       // Navigasi setelah frame selesai dibangun
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(
//             builder: (_) => HasilView(nik: nik!, nama: nama!),
//           ),
//         );
//       });
//     }
//     return Scaffold(
//       appBar: AppBar(title: Text("Face Detection ML Kit")),
//       body: _cameraController == null || !_cameraController!.value.isInitialized
//           ? Center(child: CircularProgressIndicator()) // Tampilkan loading jika kamera belum siap
//           : Stack(
//         children: [
//           CameraPreview(_cameraController!),
//           Positioned(
//             bottom: 50,
//             left: 0,
//             right: 0,
//             child: Center(
//               child: Container(
//                 padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                 decoration: BoxDecoration(
//                   color: Colors.black54,
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 child: Text(
//                   _detectionText,
//                   style: TextStyle(color: Colors.white, fontSize: 18),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'hasil_view.dart';

class PresensiView extends StatefulWidget {
  @override
  _PresensiViewState createState() => _PresensiViewState();
}

class _PresensiViewState extends State<PresensiView> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isDetecting = false;
  String _detectionText = "Mendeteksi...";
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  bool hasBlinked = false;
  bool hasTurnedHead = false;

  bool isNavigation = false;
  String? nik, nama;
  bool _isUploading = false;

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
      print("⚠️ Error in _initializeCamera: $e");
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
      if (_isDetecting) return;
      _isDetecting = true;

      try {
        final faces = await _detectFaces(image);

        if (faces.isNotEmpty) {
          _validateLiveness(faces);
        } else {
          setState(() => _detectionText = "Tidak Ada Wajah ❌");
        }
      } catch (e) {
        print("⚠️ Error Face Detection: $e");
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


  Future<void> _uploadPhoto(Uint8List imageBytes) async {
    setState(() {
      _isUploading = true;
      _detectionText = "⏳ Mengunggah foto...";
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = join(tempDir.path, 'face_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path, filename: basename(file.path)),
      });

      final response = await Dio().post(
        'http://asng-lintas.tangerangkab.my.id/api/predict',
        data: formData,
      );

      if (response.statusCode == 200 && response.data is List && response.data.length >= 2) {
        final nik = response.data[0];
        final nama = response.data[1];
        setState(() {
          _detectionText = "✅ Wajah terdeteksi: $nama";
          this.nik = nik;
          this.nama = nama;
          isNavigation = true;
        });

        debugPrint("✅ Wajah terdeteksi: $nama");
      } else {
        final message = "❌ Format data tidak dikenali dari server.";
        setState(() => _detectionText = message);
        debugPrint("$message Respon: ${response.data}");
      }
    } catch (e) {
      final message = "❌ Upload gagal: ${e.toString().split('\n').first}";
      setState(() => _detectionText = message);
      debugPrint(message);
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
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
        hasBlinked = true;
      }
    }

    if (headTurn > 15 || headTurn < -15) {
      hasTurnedHead = true;
    }

    if (hasBlinked && hasTurnedHead) {
      setState(() => _detectionText = "Liveness Verified ✅");

      await _cameraController!.stopImageStream();

      try {
        final croppedPath = await _takeAndCropFacePicture();
        if (croppedPath != null) {
          final croppedBytes = await File(croppedPath).readAsBytes();
          await _uploadPhoto(croppedBytes);
        } else {
          debugPrint("❌ Gagal cropping wajah.");
        }
      } catch (e) {
        debugPrint("❌ Gagal ambil/crop foto untuk upload: $e");
      }
    } else {
      setState(() => _detectionText = "Lakukan kedipan & putar kepala");
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final BytesBuilder bytesBuilder = BytesBuilder();
    for (Plane plane in planes) {
      if (plane.bytes.isNotEmpty) {
        bytesBuilder.add(plane.bytes);
      }
    }
    return bytesBuilder.toBytes();
  }

  @override
  void dispose() {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _cameraController!.dispose();
    }
    _faceDetector.close();
    super.dispose();
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
        debugPrint("❌ Tidak ada wajah terdeteksi saat cropping.");
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
      final croppedFile = File(croppedPath)..writeAsBytesSync(img.encodeJpg(cropped));

      return croppedPath;
    } catch (e) {
      debugPrint("❌ Error cropping wajah: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isNavigation && nik != null && nama != null) {
      isNavigation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HasilView(nik: nik!, nama: nama!),
          ),
        );
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text("Face Detection ML Kit")),
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          CameraPreview(_cameraController!),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _detectionText,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Mengunggah...",
                      style: TextStyle(color: Colors.white, fontSize: 16),
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
