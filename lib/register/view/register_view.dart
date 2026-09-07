import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'camera_page.dart';
import 'widget_template.dart';
import '../../services/api_service.dart';
import '../../models/api_error.dart';

class RegisterView extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RegisterView({super.key, required this.cameras});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController nipController = TextEditingController();
  List<File> imageFiles = [];
  bool isLoading = false;
  String _selectedMode = 'ASN'; // 'ASN' or 'NON_ASN'

  Future<void> _openGuidedCamera() async {
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final result = await Navigator.push<List<File>?>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidedCameraPage(
          camera: frontCamera,
          startFromIndex: imageFiles.length,
        ),
      ),
    );

    if (!mounted || result == null || result.isEmpty) return;

    setState(() {
      imageFiles = result;
    });
  }

  Future<void> _onSave() async {
    final name = nameController.text.trim();
    final nip = nipController.text.trim();
    final isNonAsn = _selectedMode == 'NON_ASN';
    final expectedLength = isNonAsn ? 16 : 18;
    final idLabel = isNonAsn ? 'NIK' : 'NIP';

    if (nip.length != expectedLength || int.tryParse(nip) == null) {
      _showError('$idLabel harus $expectedLength digit angka');
      return;
    }
    if (name.isEmpty) {
      _showError('Nama lengkap tidak boleh kosong');
      return;
    }
    if (imageFiles.length < 5) {
      _showError('Semua 5 pose foto wajah wajib diambil');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ApiService.registerUser(
        name: name,
        nip: nip,
        photos: imageFiles,
        role: _selectedMode,
      );

      if (!mounted) return;

      // Modern Success Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFECFDF5),
                  border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 44),
              ),
              const SizedBox(height: 18),
              const Text(
                'Registrasi Berhasil!',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.apartment_rounded, color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Instansi Anda otomatis ditetapkan berdasarkan perangkat Kiosk ini.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Data sedang menunggu persetujuan Admin OPD sebelum dapat digunakan untuk presensi.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Selesai & Kembali', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      );

      nameController.clear();
      nipController.clear();
      setState(() => imageFiles.clear());
    } on ApiError catch (e) {
      if (!mounted) return;
      _showError(e.error);
    } catch (e) {
      if (!mounted) return;
      _showError('Terjadi kendala: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNonAsn = _selectedMode == 'NON_ASN';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50
      appBar: AppBar(
        title: const Text(
          'Pendaftaran Pegawai',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══ INFO BANNER: OPD Auto-Detect ═══
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF), // Blue 50
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Instansi (OPD) otomatis terhubung ke Kiosk ini.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ═══ SLIDING SEGMENTED CONTROL (ASN / Non-ASN) ═══
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // Slate 100
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final segmentWidth = (constraints.maxWidth) / 2;
                  return Stack(
                    children: [
                      // Animated Sliding Pill Background
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOutCubic,
                        alignment: isNonAsn ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: segmentWidth,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(
                              color: isNonAsn
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                                  : const Color(0xFF2563EB).withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                      ),

                      // Segment Buttons Row
                      Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_selectedMode != 'ASN') {
                                    setState(() {
                                      _selectedMode = 'ASN';
                                      nipController.clear();
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.badge_rounded,
                                        size: 18,
                                        color: !isNonAsn ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Pegawai ASN',
                                        style: TextStyle(
                                          fontWeight: !isNonAsn ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 13,
                                          color: !isNonAsn ? const Color(0xFF1E3A8A) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_selectedMode != 'NON_ASN') {
                                    setState(() {
                                      _selectedMode = 'NON_ASN';
                                      nipController.clear();
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_rounded,
                                        size: 18,
                                        color: isNonAsn ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Pegawai Non-ASN',
                                        style: TextStyle(
                                          fontWeight: isNonAsn ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 13,
                                          color: isNonAsn ? const Color(0xFF92400E) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // Non-ASN Info Banner
            if (isNonAsn)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_rounded, color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tenaga Ahli, Honorer, Magang, dll. Gunakan NIK (16 digit).',
                        style: TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ═══ CARD 1: Data Pegawai ═══
            _buildCardContainer(
              stepNumber: '1',
              title: 'Identitas Pegawai',
              subtitle: isNonAsn ? 'Masukkan nama lengkap & 16 digit NIK' : 'Masukkan nama lengkap & 18 digit NIP',
              icon: Icons.person_outline_rounded,
              child: Column(
                children: [
                  WidgetTemplate(
                    label: 'Nama Lengkap',
                    hintText: 'Contoh: Ahmad Fauzi, S.Kom',
                    controller: nameController,
                    prefixIcon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 8),
                  WidgetTemplate(
                    label: isNonAsn ? 'Nomor Induk Kependudukan (NIK 16 Digit)' : 'Nomor Induk Pegawai (NIP 18 Digit)',
                    hintText: isNonAsn ? 'Contoh: 3603123456780001' : 'Contoh: 198501012010011001',
                    controller: nipController,
                    keyboardType: TextInputType.number,
                    maxLength: isNonAsn ? 16 : 18,
                    prefixIcon: Icons.badge_rounded,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ═══ CARD 2: Foto Wajah (Dropzone Card) ═══
            _buildCardContainer(
              stepNumber: '2',
              title: 'Perekaman Wajah Biometrik',
              subtitle: 'Pengambilan 5 sudut pose wajah untuk kecerdasan AI',
              icon: Icons.face_retouching_natural_rounded,
              child: Column(
                children: [
                  if (imageFiles.isEmpty)
                    // Modern Dropzone Card
                    GestureDetector(
                      onTap: _openGuidedCamera,
                      child: CustomPaint(
                        painter: DashedBorderPainter(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.6),
                          strokeWidth: 1.8,
                          dashWidth: 6,
                          dashSpace: 4,
                          borderRadius: 20,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFEFF6FF),
                                  border: Border.all(color: const Color(0xFFDBEAFE), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add_a_photo_rounded,
                                  size: 32,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Mulai Ambil 5 Foto Wajah',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Panduan interaktif (Tengah, Kiri, Kanan, Senyum, Netral)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 6),
                                    Text(
                                      'Buka Kamera',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        // Progress Bar & Count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: imageFiles.length / 5,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                '${imageFiles.length}/5 Lengkap',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Photo Thumbnails Grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: imageFiles.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemBuilder: (context, index) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(imageFiles[index], fit: BoxFit.cover),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        'Pose ${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Retake Action Button
                        TextButton.icon(
                          onPressed: () {
                            setState(() => imageFiles.clear());
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Ambil Ulang Semua Pose', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ═══ SUBMIT BUTTON ═══
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (isLoading || imageFiles.length < 5) ? null : _onSave,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  isLoading ? 'Menyimpan Data Pegawai...' : 'Kirim Pendaftaran Pegawai',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF93C5FD).withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Modern Section Card Container
  Widget _buildCardContainer({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  stepNumber,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, color: const Color(0xFF94A3B8), size: 20),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Dashed Border Painter for Modern Upload Dropzones
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 6.0,
    this.dashSpace = 4.0,
    this.borderRadius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    final dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = (distance + dashWidth < metric.length) ? dashWidth : metric.length - distance;
        dashedPath.addPath(metric.extractPath(distance, distance + length), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace ||
        oldDelegate.borderRadius != borderRadius;
  }
}
