import 'dart:async';
import 'package:asng/register/view/register_view.dart' show RegisterView;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'presensi_view.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistem Presensi ASN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(cameras: cameras),
    );
  }
}

class MyHomePage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyHomePage({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/bgnew.jpg', // pastikan gambar ini ada di pubspec.yaml
              fit: BoxFit.cover,
            ),
          ),
          // Content overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3), // Optional dark overlay
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Sistem Presensi Untuk ASN Kab Tangerang',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      children: [
                        _buildButton(context, Icons.fingerprint, 'Presensi'),
                        _buildButton(context, Icons.app_registration, 'Register'),
                        _buildButton(context, Icons.person, 'User List'),
                        _buildButton(context, Icons.logout, 'Logout'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, IconData icon, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.8),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(16),
      ),
      onPressed: () {
        if (label == 'Presensi') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PresensiView()),
          );
        } else if (label == 'Register') {
          Navigator.push(
            context,
              MaterialPageRoute(builder: (context) => RegisterView(cameras: cameras))
          );
        } else if (label == 'User List') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fitur belum tersedia')),
          );
        } else if (label == 'Logout') {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Konfirmasi'),
              content: const Text('Yakin ingin keluar?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // tutup dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Berhasil logout')),
                    );
                  },
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
