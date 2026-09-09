import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'services/api_service.dart';
import 'models/api_error.dart';
import 'main.dart'; // for `cameras`

/// Presensi Kegiatan — camera page for activity-based attendance.
/// Takes a photo and sends it to POST /api/predict/kegiatan.
class PresensiKegiatanView extends StatefulWidget {
  final int kegiatanId;
  final String kegiatanName;

  const PresensiKegiatanView({
    super.key,
    required this.kegiatanId,
    required this.kegiatanName,
  });

  @override
  State<PresensiKegiatanView> createState() => _PresensiKegiatanViewState();
}

class _PresensiKegiatanViewState extends State<PresensiKegiatanView> {
  CameraController? _camController;
  bool _isProcessing = false;
  String? _resultMessage;
  bool? _resultSuccess;
  Timer? _autoReturnTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camController = CameraController(front, ResolutionPreset.medium);
    await _camController!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _camController?.dispose();
    _autoReturnTimer?.cancel();
    super.dispose();
  }

  Future<Position?> _getPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 5)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _capture() async {
    if (_isProcessing || _camController == null || !_camController!.value.isInitialized) return;
    setState(() { _isProcessing = true; _resultMessage = null; _resultSuccess = null; });

    try {
      final xFile = await _camController!.takePicture();
      final photo = File(xFile.path);
      final pos = await _getPosition();

      final result = await ApiService.predictKegiatan(
        photo,
        kegiatanId: widget.kegiatanId,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );

      final name = result['name']?.toString() ?? '';
      final status = result['status']?.toString() ?? '';
      final waktu = result['waktu']?.toString() ?? '';
      final isDuplicate = result['is_duplicate'] == true;

      setState(() {
        _resultSuccess = true;
        _resultMessage = isDuplicate
          ? '⚠️ $name\n$status\nWaktu: $waktu'
          : '✅ $name\n$status\nWaktu: $waktu';
      });

      _autoReturn(5);
    } on ApiError catch (e) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = '❌ ${e.error}';
      });
      _autoReturn(4);
    } catch (e) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = '❌ Terjadi kesalahan: $e';
      });
      _autoReturn(4);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _autoReturn(int seconds) {
    _autoReturnTimer?.cancel();
    _autoReturnTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        setState(() { _resultMessage = null; _resultSuccess = null; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.shortestSide;
    final camReady = _camController != null && _camController!.value.isInitialized;

    return Scaffold(
      body: Stack(
        children: [
          // Camera preview
          if (camReady)
            Positioned.fill(child: CameraPreview(_camController!))
          else
            const Positioned.fill(child: ColoredBox(color: Colors.black)),

          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.all(s * 0.04),
                padding: EdgeInsets.symmetric(horizontal: s * 0.04, vertical: s * 0.025),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(s * 0.03),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, color: Colors.white, size: s * 0.06),
                    ),
                    SizedBox(width: s * 0.03),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Presensi Kegiatan',
                            style: TextStyle(fontSize: s * 0.035, color: Colors.white70)),
                          Text(widget.kegiatanName,
                            style: TextStyle(fontSize: s * 0.04, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Result overlay
          if (_resultMessage != null)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    margin: EdgeInsets.all(s * 0.1),
                    padding: EdgeInsets.all(s * 0.06),
                    decoration: BoxDecoration(
                      color: _resultSuccess == true ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(s * 0.05),
                      border: Border.all(
                        color: _resultSuccess == true ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _resultSuccess == true ? Icons.check_circle : Icons.error,
                          size: s * 0.15,
                          color: _resultSuccess == true ? Colors.green : Colors.red,
                        ),
                        SizedBox(height: s * 0.04),
                        Text(_resultMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: s * 0.04, fontWeight: FontWeight.w600,
                            color: _resultSuccess == true ? Colors.green[800] : Colors.red[800])),
                        SizedBox(height: s * 0.04),
                        Text('Kembali otomatis...',
                          style: TextStyle(fontSize: s * 0.03, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Capture button
          if (_resultMessage == null)
            Positioned(
              bottom: s * 0.1, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isProcessing ? null : _capture,
                  child: Container(
                    width: s * 0.2,
                    height: s * 0.2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isProcessing ? Colors.grey : Colors.white,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [BoxShadow(color: Colors.black38, blurRadius: s * 0.03)],
                    ),
                    child: _isProcessing
                      ? Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple))
                      : Icon(Icons.camera_alt, size: s * 0.08, color: Colors.deepPurple),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
