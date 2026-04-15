import 'dart:async';
import 'package:flutter/material.dart';
import 'presensi_view.dart';

/// Displays the attendance result (name, time, status) after successful face recognition.
/// Auto-returns to PresensiView after 5 seconds for the next person (kiosk mode).
class HasilView extends StatefulWidget {
  final String name;
  final String waktu;
  final String status;

  const HasilView({
    super.key,
    required this.name,
    required this.waktu,
    required this.status,
  });

  @override
  State<HasilView> createState() => _HasilViewState();
}

class _HasilViewState extends State<HasilView> {
  int _countdown = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
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
    super.dispose();
  }

  bool get _isOnTime => widget.status == 'ON_TIME';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isOnTime ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isOnTime ? Icons.check_circle_outline : Icons.access_time_filled,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),

                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _isOnTime ? '✅ TEPAT WAKTU' : '⚠️ TERLAMBAT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Result card
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
                      Row(
                        children: [
                          Icon(Icons.person, color: Colors.grey.shade600, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nama',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                Text(
                                  widget.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      // Time
                      Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.grey.shade600, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Waktu Presensi',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                Text(
                                  widget.waktu,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      // Status
                      Row(
                        children: [
                          Icon(
                            _isOnTime ? Icons.thumb_up : Icons.warning_amber_rounded,
                            color: _isOnTime ? Colors.green.shade700 : Colors.red.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                Text(
                                  widget.status,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _isOnTime ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Auto-return countdown
                Text(
                  'Kembali ke kamera dalam $_countdown detik...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),

                // Manual return button
                TextButton.icon(
                  onPressed: _navigateBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text(
                    'Kembali Sekarang',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
