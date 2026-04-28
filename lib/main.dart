import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'presensi_view.dart';
import 'register/view/register_view.dart';
import 'settings/settings_view.dart';
import 'services/api_service.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  
  // Anti-spoofing sekarang berjalan server-side (Flask /api/check-spoof)
  // Tidak perlu init SDK di client

  // Kirim heartbeat ke server di background
  ApiService.sendHeartbeat();

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
    // Step 10: Block back button on home screen (kiosk mode)
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            // Background image
            Positioned.fill(
              child: Image.asset(
                'assets/images/bgnew.jpg',
                fit: BoxFit.cover,
              ),
            ),
            // Content overlay
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Step 2: Long-press on title to access hidden Settings
                    GestureDetector(
                      onLongPress: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsView()),
                        );
                      },
                      child: const Text(
                        'Sistem Presensi Untuk ASN\nKab Tangerang',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
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
                          _buildButton(context, Icons.settings, 'Settings'),
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
      ),
    );
  }

  Widget _buildButton(BuildContext context, IconData icon, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.8),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(16),
      ),
      onPressed: () {
        if (label == 'Presensi') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PresensiView()),
          );
        } else if (label == 'Register') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RegisterView(cameras: cameras)),
          );
        } else if (label == 'Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsView()),
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
                    Navigator.pop(context);
                    SystemNavigator.pop();
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
