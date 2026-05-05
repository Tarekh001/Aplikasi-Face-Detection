import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'config/app_config.dart';
import 'presensi_view.dart';
import 'services/api_service.dart';
import 'activation/activation_view.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();

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
      home: SplashRouter(cameras: cameras),
    );
  }
}

/// Splash/Router — checks binding state on startup and routes accordingly.
class SplashRouter extends StatefulWidget {
  final List<CameraDescription> cameras;
  const SplashRouter({super.key, required this.cameras});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  bool _isLoading = true;
  bool _isBound = false;

  @override
  void initState() {
    super.initState();
    _checkBindingState();
  }

  Future<void> _checkBindingState() async {
    final isBound = await AppConfig.getIsBound();
    if (!mounted) return;
    setState(() {
      _isBound = isBound;
      _isLoading = false;
    });
  }

  void _onDeviceBound() {
    setState(() => _isBound = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isBound) {
      return ActivationView(onBound: _onDeviceBound);
    }

    return const KioskHomePage();
  }
}

/// Kiosk Home — Clean single-purpose screen.
/// Only shows "Presensi" button. Admin menus are hidden behind
/// biometric face unlock in PresensiView.
class KioskHomePage extends StatefulWidget {
  const KioskHomePage({super.key});

  @override
  State<KioskHomePage> createState() => _KioskHomePageState();
}

class _KioskHomePageState extends State<KioskHomePage> {
  String _opdName = '-';

  @override
  void initState() {
    super.initState();
    _loadOpdName();
  }

  Future<void> _loadOpdName() async {
    final name = await AppConfig.getBoundOpdName();
    if (mounted) setState(() => _opdName = name);
  }

  @override
  Widget build(BuildContext context) {
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
                color: Colors.black.withValues(alpha: 0.4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Sistem Presensi Untuk ASN\nKab Tangerang',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _opdName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),

                    // Single large "Presensi" button
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PresensiView()),
                        );
                      },
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint, size: 64, color: Colors.deepPurple),
                            SizedBox(height: 12),
                            Text('Presensi',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                    Text(
                      'Menu Admin tersedia melalui verifikasi wajah\ndi halaman Presensi (ikon ⚙️)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
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
}
