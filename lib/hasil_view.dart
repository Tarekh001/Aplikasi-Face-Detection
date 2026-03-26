import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class HasilView extends StatelessWidget {
  final String nik;
  final String nama;

  const HasilView({super.key, required this.nik, required this.nama});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Hasil Deteksi")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("✅ Data Diterima", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text("NIK: $nik", style: TextStyle(fontSize: 18)),
            Text("Nama: $nama", style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
