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

    if (nip.length != 18 || int.tryParse(nip) == null) {
      _showError('NIP harus 18 digit angka');
      return;
    }
    if (name.isEmpty) {
      _showError('Nama tidak boleh kosong');
      return;
    }
    if (imageFiles.length < 5) {
      _showError('Semua 5 foto wajah harus diambil');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ApiService.registerUser(
        name: name,
        nip: nip,
        photos: imageFiles,
      );

      if (!mounted) return;

      // Success Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300, width: 3),
                ),
                child: Icon(Icons.check_rounded, color: Colors.green.shade600, size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                'Registrasi Berhasil!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.apartment_rounded, color: Colors.blue.shade700, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Instansi Anda otomatis ditentukan berdasarkan perangkat Kiosk ini.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded, color: Colors.amber.shade700, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Data Anda sedang menunggu persetujuan Admin OPD sebelum dapat digunakan untuk absen.',
                        style: TextStyle(fontSize: 13, height: 1.4),
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
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      _showError('Kesalahan: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ $message'), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Pegawai'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══ INFO BANNER: OPD Auto-Detect ═══
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Instansi (OPD) akan otomatis ditetapkan berdasarkan perangkat Kiosk ini.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ═══ STEP 1: Data Pegawai ═══
            _buildSectionHeader('1', 'Data Pegawai', Icons.person_outline),
            const SizedBox(height: 14),

            WidgetTemplate(label: 'Nama Lengkap', controller: nameController),
            const SizedBox(height: 4),
            WidgetTemplate(
              label: 'NIP (18 digit)',
              controller: nipController,
              keyboardType: TextInputType.number,
              maxLength: 18,
            ),

            const SizedBox(height: 28),

            // ═══ STEP 2: Foto Wajah ═══
            _buildSectionHeader('2', 'Foto Wajah (5 Pose)', Icons.camera_alt_outlined),
            const SizedBox(height: 14),

            // Photo grid with status
            if (imageFiles.isEmpty)
              // Empty state: Big CTA button
              GestureDetector(
                onTap: _openGuidedCamera,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.deepPurple.shade200, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.add_a_photo_rounded, size: 56, color: Colors.deepPurple.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Mulai Ambil 5 Foto Wajah',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dibimbing langkah demi langkah',
                        style: TextStyle(fontSize: 13, color: Colors.deepPurple.shade400),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  // Progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: imageFiles.length / 5,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              imageFiles.length == 5 ? Colors.green : Colors.deepPurple,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${imageFiles.length}/5',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: imageFiles.length == 5 ? Colors.green.shade700 : Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Photo thumbnails
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
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(imageFiles[index], fit: BoxFit.cover),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  'Pose ${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Retake button
                  TextButton.icon(
                    onPressed: () {
                      setState(() => imageFiles.clear());
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Ulangi Semua Foto'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                  ),
                ],
              ),

            const SizedBox(height: 28),

            // ═══ SUBMIT BUTTON ═══
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: (isLoading || imageFiles.length < 5) ? null : _onSave,
                icon: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  isLoading ? 'Mengirim Data...' : 'KIRIM REGISTRASI',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── UI Helper Widgets ──

  Widget _buildSectionHeader(String step, String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.deepPurple,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: Colors.deepPurple, size: 22),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}
