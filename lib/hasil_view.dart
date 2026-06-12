import 'dart:async';
import 'package:flutter/material.dart';
import 'presensi_view.dart';
import 'models/predict_response.dart';

// ── Theme data for each attendance state ──
class _ResultTheme {
  final Color bgColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;

  const _ResultTheme({
    required this.bgColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
  });
}

/// Displays the attendance result after face recognition.
/// Dynamically themed based on status (ON_TIME, LATE, OUT, UNKNOWN).
/// Auto-returns to PresensiView after countdown (kiosk mode).
class HasilView extends StatefulWidget {
  final PredictResponse result;

  const HasilView({super.key, required this.result});

  @override
  State<HasilView> createState() => _HasilViewState();
}

class _HasilViewState extends State<HasilView> with SingleTickerProviderStateMixin {
  int _countdown = 5;
  Timer? _timer;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
    _startCountdown();
  }

  _ResultTheme _getTheme() {
    final r = widget.result;

    // STATE 4: UNRECOGNIZED
    if (r.isUnknown) {
      return const _ResultTheme(
        bgColor: Color(0xFFE65100), // deep orange
        icon: Icons.face_retouching_off,
        title: 'WAJAH TIDAK DIKENALI',
        subtitle: 'Silakan presensi ulang.\nPastikan pencahayaan terang dan wajah terlihat jelas.',
        buttonLabel: 'Coba Lagi',
      );
    }

    // STATE 3: OUT
    if (r.tipeAbsen == 'OUT') {
      return const _ResultTheme(
        bgColor: Color(0xFF1565C0), // blue
        icon: Icons.logout_rounded,
        title: 'PULANG BERHASIL',
        subtitle: 'Presensi Pulang Tercatat',
        buttonLabel: 'Kembali',
      );
    }

    // STATE 2: IN + LATE
    if (r.tipeAbsen == 'IN' && r.isLate) {
      return _ResultTheme(
        bgColor: const Color(0xFFB71C1C), // red
        icon: Icons.access_time_filled,
        title: 'TERLAMBAT',
        subtitle: 'Presensi Masuk Tercatat\nTerlambat ${r.keterlambatanMenit} Menit',
        buttonLabel: 'Kembali',
      );
    }

    // STATE 1: IN + ON_TIME (default)
    return const _ResultTheme(
      bgColor: Color(0xFF1B5E20), // green
      icon: Icons.check_circle_outline,
      title: 'MASUK BERHASIL',
      subtitle: 'Presensi Masuk Tepat Waktu',
      buttonLabel: 'Kembali',
    );
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _navigateBack();
      }
    });
  }

  void _navigateBack() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PresensiView()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getTheme();
    final r = widget.result;
    final bool isUnknown = r.isUnknown;

    return Scaffold(
      backgroundColor: theme.bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Animated Status Icon ──
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
                    ),
                    child: Icon(theme.icon, size: 72, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Title Badge ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    theme.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Subtitle ──
                Text(
                  theme.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Detail Card (only for recognized users) ──
                if (!isUnknown)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Name
                        _buildDetailRow(
                          icon: Icons.person,
                          label: 'Nama',
                          value: r.name,
                          color: Colors.grey.shade700,
                        ),
                        const Divider(height: 28),

                        // Time
                        _buildDetailRow(
                          icon: Icons.schedule,
                          label: 'Waktu Presensi',
                          value: r.waktu,
                          color: Colors.grey.shade700,
                        ),
                        const Divider(height: 28),

                        // Status
                        _buildDetailRow(
                          icon: r.isLate ? Icons.warning_amber_rounded : Icons.thumb_up_rounded,
                          label: 'Status',
                          value: r.isLate
                              ? 'Terlambat ${r.keterlambatanMenit} Menit'
                              : r.tipeAbsen == 'OUT'
                                  ? 'Pulang'
                                  : 'Tepat Waktu',
                          color: r.isLate ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 28),

                // ── Countdown ──
                Text(
                  'Kembali ke kamera dalam $_countdown detik...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Manual Return Button ──
                TextButton.icon(
                  onPressed: _navigateBack,
                  icon: Icon(
                    isUnknown ? Icons.refresh : Icons.arrow_back,
                    color: Colors.white,
                  ),
                  label: Text(
                    theme.buttonLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
