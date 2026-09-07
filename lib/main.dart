import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'presensi_view.dart';
import 'kegiatan_select_view.dart';
import 'services/api_service.dart';
import 'activation/activation_view.dart';
import 'settings/settings_view.dart';

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
      title: 'Sistem Presensi Smart City',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
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
  String _opdName = 'Memuat Instansi...';
  int _secretTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _loadOpdName();
  }

  Future<void> _loadOpdName() async {
    final name = await AppConfig.getBoundOpdName();
    if (mounted) setState(() => _opdName = name.isEmpty ? 'Pemerintah Kab. Tangerang' : name);
  }

  /// Secret Gesture: 7x Tap to open Server & Device IP Configuration
  void _handleSecretTap() {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!) > const Duration(seconds: 3)) {
      _secretTapCount = 1;
    } else {
      _secretTapCount++;
    }
    _lastTapTime = now;

    if (_secretTapCount >= 7) {
      _secretTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsView()),
      );
    } else if (_secretTapCount >= 4) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ketuk ${7 - _secretTapCount}x lagi untuk membuka Pengaturan Server',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          duration: const Duration(milliseconds: 600),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 24, left: 32, right: 32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F172A), // Slate 900
                Color(0xFF1E293B), // Slate 800
              ],
            ),
          ),
          child: SafeArea(
            child: OrientationBuilder(
              builder: (context, orientation) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = orientation == Orientation.landscape;
                    final isTablet = constraints.maxWidth >= 600 || MediaQuery.of(context).size.shortestSide >= 600;
                    final useRowCards = isLandscape || isTablet;

                    return Stack(
                      children: [
                        // Decorative Ambient Glows
                        Positioned(
                          top: -60,
                          left: -60,
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -80,
                          right: -80,
                          child: Container(
                            width: 280,
                            height: 280,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF10B981).withValues(alpha: 0.08),
                            ),
                          ),
                        ),

                        // Scrollable Container to prevent any pixel overflow
                        SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: IntrinsicHeight(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 36.0 : 20.0,
                                  vertical: isLandscape ? 12.0 : 20.0,
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 8),

                                    // --- 1. BRANDING HEADER ---
                                    _buildBrandingHeader(isTablet, isLandscape),

                                    const SizedBox(height: 10),

                                    // --- 2. SECRET GESTURE OPD PILL CONTAINER ---
                                    _buildOpdPill(),

                                    SizedBox(height: isLandscape ? 12 : 20),

                                    // --- 3. ADAPTIVE BENTO MENU PRESENSI ---
                                    if (useRowCards)
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: _buildBentoCard(
                                                context: context,
                                                title: 'Presensi\nHarian',
                                                subtitle: 'Scan Wajah Masuk & Pulang',
                                                badgeText: 'Reguler',
                                                badgeColor: const Color(0xFF3B82F6),
                                                primaryColor: const Color(0xFF2563EB),
                                                accentColor: const Color(0xFF60A5FA),
                                                icon: Icons.fingerprint_rounded,
                                                isCompact: isLandscape && constraints.maxHeight < 500,
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(builder: (_) => const PresensiView()),
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: _buildBentoCard(
                                                context: context,
                                                title: 'Presensi\nKegiatan',
                                                subtitle: 'Acara & Tugas Luar Kantor',
                                                badgeText: 'Khusus',
                                                badgeColor: const Color(0xFF10B981),
                                                primaryColor: const Color(0xFF059669),
                                                accentColor: const Color(0xFF34D399),
                                                icon: Icons.event_available_rounded,
                                                isCompact: isLandscape && constraints.maxHeight < 500,
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(builder: (_) => const KegiatanSelectView()),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Column(
                                        children: [
                                          _buildHorizontalBentoCard(
                                            context: context,
                                            title: 'Presensi Harian',
                                            subtitle: 'Scan Wajah Masuk & Pulang ASN/Non-ASN',
                                            badgeText: 'Reguler',
                                            badgeColor: const Color(0xFF3B82F6),
                                            primaryColor: const Color(0xFF2563EB),
                                            accentColor: const Color(0xFF60A5FA),
                                            icon: Icons.fingerprint_rounded,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (_) => const PresensiView()),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 14),
                                          _buildHorizontalBentoCard(
                                            context: context,
                                            title: 'Presensi Kegiatan',
                                            subtitle: 'Presensi Acara & Tugas Luar Kantor',
                                            badgeText: 'Khusus',
                                            badgeColor: const Color(0xFF10B981),
                                            primaryColor: const Color(0xFF059669),
                                            accentColor: const Color(0xFF34D399),
                                            icon: Icons.event_available_rounded,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (_) => const KegiatanSelectView()),
                                              );
                                            },
                                          ),
                                        ],
                                      ),

                                    SizedBox(height: isLandscape ? 10 : 18),

                                    // --- 4. FOOTER NOTE (Overflow fixed with Flexible) ---
                                    _buildFooterNote(),
                                    const SizedBox(height: 6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Branding Header Component
  Widget _buildBrandingHeader(bool isTablet, bool isLandscape) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 13, color: Color(0xFF60A5FA)),
              SizedBox(width: 6),
              Text(
                'SMART PRESENSI BIOMETRIK',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF93C5FD),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pemerintah Kabupaten Tangerang',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isTablet ? 26 : (isLandscape ? 18 : 21),
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  /// Secret Gesture OPD Pill Container (7x Tap)
  Widget _buildOpdPill() {
    return GestureDetector(
      onTap: _handleSecretTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.apartment_rounded,
              size: 15,
              color: Color(0xFF60A5FA),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _opdName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tall Bento Card (for Tablet Portrait & Landscape)
  Widget _buildBentoCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color primaryColor,
    required Color accentColor,
    required IconData icon,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: primaryColor.withValues(alpha: 0.2),
          highlightColor: primaryColor.withValues(alpha: 0.1),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: isCompact ? 14 : 22,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top Tag Badge
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: isCompact ? 4 : 10),

                // Large Glowing Icon Orb
                Container(
                  width: isCompact ? 52 : 72,
                  height: isCompact ? 52 : 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withValues(alpha: 0.18),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.25),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: isCompact ? 28 : 38,
                    color: Colors.white,
                  ),
                ),

                SizedBox(height: isCompact ? 8 : 16),

                // Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 5),

                // Subtitle
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                    height: 1.25,
                  ),
                ),

                SizedBox(height: isCompact ? 10 : 16),

                // Action Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Mulai Presensi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Elongated Horizontal Bento Card (for Phone Portrait)
  Widget _buildHorizontalBentoCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color primaryColor,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: primaryColor.withValues(alpha: 0.2),
          highlightColor: primaryColor.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                // Glowing Icon Orb
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withValues(alpha: 0.2),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.25),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(width: 14),

                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Arrow Circle
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Footer Note Component (Fixes right overflow with Flexible)
  Widget _buildFooterNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 15,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Menu Admin: Buka Layar Presensi lalu tap ikon ⚙️ (Verifikasi Wajah)',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
