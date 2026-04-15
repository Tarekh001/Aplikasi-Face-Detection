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

  Future<void> _openCamera() async {
    if (imageFiles.length >= 5) return;

    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final image = await Navigator.push<File?>(
      context,
      MaterialPageRoute(builder: (_) => CameraPage(camera: frontCamera)),
    );

    if (!mounted) return;

    if (image != null) {
      setState(() => imageFiles.add(image));
    }
  }

  Future<void> _onSave() async {
    final name = nameController.text.trim();
    final nip = nipController.text.trim();

    if (nip.length != 18 || int.tryParse(nip) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NIP harus 18 digit angka')),
      );
      return;
    }

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama tidak boleh kosong')),
      );
      return;
    }

    if (imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal 1 foto harus diambil')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Use centralized ApiService instead of hardcoded Dio call
      await ApiService.registerUser(
        name: name,
        nip: nip,
        photos: imageFiles,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Registrasi berhasil'),
          backgroundColor: Colors.green,
        ),
      );
      nameController.clear();
      nipController.clear();
      setState(() => imageFiles.clear());
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.error}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Kesalahan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Pegawai')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            WidgetTemplate(
              label: 'Nama Lengkap',
              controller: nameController,
            ),
            WidgetTemplate(
              label: 'NIP (18 digit)',
              controller: nipController,
              keyboardType: TextInputType.number,
              maxLength: 18,
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: imageFiles.length < 5 ? imageFiles.length + 1 : 5,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                if (index < imageFiles.length) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Image.file(
                          imageFiles[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => imageFiles.removeAt(index));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  return GestureDetector(
                    onTap: _openCamera,
                    child: Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(Icons.add_a_photo, size: 40),
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : _onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'SIMPAN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
