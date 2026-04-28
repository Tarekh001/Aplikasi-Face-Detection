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

  // OPD State
  List<dynamic> opdList = [];
  int? selectedOpdId;
  bool isLoadingOpd = true;

  @override
  void initState() {
    super.initState();
    _fetchOpdList();
  }

  Future<void> _fetchOpdList() async {
    setState(() => isLoadingOpd = true);
    try {
      final list = await ApiService.fetchOpdList();
      if (!mounted) return;
      setState(() {
        opdList = list.map((opd) => {
          ...opd,
          'id': int.parse(opd['id'].toString()),
        }).toList();
        if (opdList.length == 1) {
          selectedOpdId = opdList[0]['id'] as int;
        }
        isLoadingOpd = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoadingOpd = false);
      debugPrint('⚠️ Gagal mengambil OPD: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal memuat daftar instansi. Periksa koneksi server.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openGuidedCamera() async {
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    // Open guided camera — returns List<File> of 5 photos, or null if cancelled
    final result = await Navigator.push<List<File>?>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidedCameraPage(
          camera: frontCamera,
          startFromIndex: imageFiles.length, // resume from where we left off
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

    if (selectedOpdId == null) {
      _showError('Pilih Instansi (OPD) terlebih dahulu');
      return;
    }
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
        opdId: selectedOpdId!,
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
              // Animated checkmark circle
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
      setState(() {
        imageFiles.clear();
        selectedOpdId = opdList.length == 1 ? opdList[0]['id'] : null;
      });
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
    final bool formReady = selectedOpdId != null &&
        nameController.text.trim().isNotEmpty &&
        nipController.text.trim().length == 18;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Pegawai'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══ STEP 1: Data Pegawai ═══
            _buildSectionHeader('1', 'Data Pegawai', Icons.person_outline),
            const SizedBox(height: 12),

            // OPD Dropdown
            _buildLabel('Instansi (OPD)'),
            const SizedBox(height: 6),
            if (isLoadingOpd)
              _buildLoadingBox('Memuat data instansi...')
            else if (opdList.isEmpty)
              _buildErrorBox('Gagal memuat instansi. Ketuk untuk coba lagi.', _fetchOpdList)
            else
              DropdownButtonFormField<int>(
                value: selectedOpdId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: '-- Pilih Instansi --',
                  prefixIcon: const Icon(Icons.apartment, color: Colors.deepPurple),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                items: opdList.map<DropdownMenuItem<int>>((opd) {
                  final int id = int.parse(opd['id'].toString());
                  final String nama = opd['nama']?.toString() ?? '-';
                  final String kode = opd['kode']?.toString() ?? '';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('$nama ($kode)', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (int? v) => setState(() => selectedOpdId = v),
              ),

            const SizedBox(height: 12),

            WidgetTemplate(label: 'Nama Lengkap', controller: nameController),
            WidgetTemplate(
              label: 'NIP (18 digit)',
              controller: nipController,
              keyboardType: TextInputType.number,
              maxLength: 18,
            ),

            const SizedBox(height: 24),

            // ═══ STEP 2: Foto Wajah ═══
            _buildSectionHeader('2', 'Foto Wajah (5 Pose)', Icons.camera_alt_outlined),
            const SizedBox(height: 12),

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

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87));
  }

  Widget _buildLoadingBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey.shade100,
      ),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(10),
          color: Colors.red.shade50,
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
