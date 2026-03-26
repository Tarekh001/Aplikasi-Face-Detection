import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'camera_page.dart';
import 'widget_template.dart';

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

  Future<File> copyAssetImageToFile(String assetPath, String filename) async {
    final byteData = await rootBundle.load(assetPath);

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');

    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  @override
  Widget build(BuildContext context) {



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
        final file = await copyAssetImageToFile('assets/images/contoh.png', 'bgnew.jpg');
       // setState(() => imageFiles.add(file));
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
        // 🔧 Log input
        print('🔧 Mengirim data registrasi...');
        print('🧑 Nama: $name');
        print('🆔 NIP: $nip');

        // Siapkan FormData
        final formData = FormData.fromMap({
          'name': name,
          'nip': nip,
          'photos': [
            for (int i = 0; i < imageFiles.length; i++)
              await MultipartFile.fromFile(
                imageFiles[i].path,
                filename: basename(imageFiles[i].path),
              )
          ]
        });

        // Log file
        for (int i = 0; i < imageFiles.length; i++) {
          print('📸 Foto${i + 1}: ${basename(imageFiles[i].path)}');
        }

        final dio = Dio();
        // dio.options.headers['Authorization'] =
        // 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJmcmVzaCI6ZmFsc2UsImlhdCI6MTc1MDgyMzEzMCwianRpIjoiMGZkNTFiNjMtYTU3Mi00ZDgxLWI2YTAtMjllODU0ZTdkNGIzIiwidHlwZSI6ImFjY2VzcyIsInN1YiI6ImFkbWluIiwibmJmIjoxNzUwODIzMTMwLCJjc3JmIjoiMzkwNGU2NjMtODg4MC00MTU5LWExZDEtODJiMDBmMjg3NjMyIiwiZXhwIjoxNzUyMDMyNzMwLCJyb2xlIjoiYWRtaW4ifQ.FX0xgWiLmrFtTo8xtpauzAsyv9PTUMrF50nXdNCT7fI';

        final response = await dio.post(
          'http://asng-lintas.tangerangkab.my.id/api/register',
          data: formData,
        );

        if (!mounted) return;

        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registrasi berhasil')),
          );
          nameController.clear();
          nipController.clear();
          setState(() => imageFiles.clear());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal: ${response.statusMessage}')),
          );
        }
      } on DioException catch (e) {
        if (!mounted) return;

        String errorMessage = 'Terjadi kesalahan saat mengirim data';

        if (e.response != null) {
          print('❌ Dio Error Response: ${e.response?.data}');
          print('❌ Status Code: ${e.response?.statusCode}');
          errorMessage = 'Gagal: ${e.response?.data['message'] ?? e.response?.statusMessage}';
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = 'Timeout: Tidak dapat menghubungi server';
        } else {
          errorMessage = 'Kesalahan jaringan: ${e.message}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kesalahan tak terduga: $e')),
        );
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }


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
                  return Image.file(
                    imageFiles[index],
                    fit: BoxFit.cover,
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
