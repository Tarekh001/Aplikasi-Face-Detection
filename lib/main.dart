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

  // Lock orientation to portrait for kiosk tablets
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Hide system UI for immersive kiosk mode
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
    final s = MediaQuery.of(context).size.shortestSide;
    final buttonSize = s * 0.45;

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
                    Text(
                      'Sistem Presensi Untuk ASN\nKab Tangerang',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: s * 0.065,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: s * 0.02),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: s * 0.04, vertical: s * 0.015),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(s * 0.05),
                      ),
                      child: Text(
                        _opdName,
                        style: TextStyle(
                          fontSize: s * 0.035,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: s * 0.12),

                    // Single large "Presensi" button
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PresensiView()),
                        );
                      },
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(s * 0.06),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: s * 0.05,
                              offset: Offset(0, s * 0.02),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint, size: s * 0.16, color: Colors.deepPurple),
                            SizedBox(height: s * 0.03),
                            Text('Presensi',
                                style: TextStyle(
                                    fontSize: s * 0.05,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: s * 0.07),
                    Text(
                      'Menu Admin tersedia melalui verifikasi wajah\ndi halaman Presensi (ikon ⚙️)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: s * 0.03,
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
