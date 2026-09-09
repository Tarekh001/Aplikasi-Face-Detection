import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'package:dio/dio.dart';

/// Hidden Settings screen for admin/technician to configure:
/// - Server IP Address
/// - Device Serial Number (SN)
///
/// Access: Long-press on app title in Home Page
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _snController = TextEditingController();
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final baseUrl = await AppConfig.getBaseUrl();
    final deviceSn = await AppConfig.getDeviceSn();
    _ipController.text = baseUrl;
    _snController.text = deviceSn;
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final ip = _ipController.text.trim();
    final sn = _snController.text.trim();

    if (ip.isEmpty || sn.isEmpty) {
      _showSnackBar('Server IP dan Device SN tidak boleh kosong', isError: true);
      return;
    }

    await AppConfig.setBaseUrl(ip);
    await AppConfig.setDeviceSn(sn);
    _showSnackBar('✅ Pengaturan berhasil disimpan');
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final baseUrl = _ipController.text.trim();
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.receiveTimeout = const Duration(seconds: 5);

      // Simple GET to check if server is reachable
      final response = await dio.get('$baseUrl/');
      setState(() {
        _testResult = '✅ Server terhubung (Status: ${response.statusCode})';
      });
    } on DioException catch (e) {
      String message;
      if (e.type == DioExceptionType.connectionTimeout) {
        message = '❌ Timeout: Server tidak merespon';
      } else if (e.type == DioExceptionType.connectionError) {
        message = '❌ Tidak dapat terhubung ke server';
      } else if (e.response != null) {
        // Server responded but with an error — it's still reachable
        message = '✅ Server terhubung (Status: ${e.response?.statusCode})';
      } else {
        message = '❌ Error: ${e.message}';
      }
      setState(() => _testResult = message);
    } catch (e) {
      setState(() => _testResult = '❌ Error: $e');
    } finally {
      setState(() => _isTesting = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _snController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ Pengaturan Perangkat'),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Halaman ini hanya untuk Admin/Teknisi.\nPerubahan akan mempengaruhi koneksi ke server.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Server IP field
                  const Text(
                    'Server IP Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      hintText: 'Contoh: http://192.168.100.57:5000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.dns),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 20),

                  // Device SN field
                  const Text(
                    'Device Serial Number (SN)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _snController,
                    decoration: InputDecoration(
                      hintText: 'Contoh: KIOSK_DUKCAPIL_01',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.perm_device_information),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'SN harus sesuai dengan yang didaftarkan di Dashboard oleh Super Admin.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 30),

                  // Test Connection button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(_isTesting ? 'Menghubungi server...' : 'Test Koneksi'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),

                  // Test result
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _testResult!.startsWith('✅')
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _testResult!.startsWith('✅')
                              ? Colors.green.shade300
                              : Colors.red.shade300,
                        ),
                      ),
                      child: Text(_testResult!, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text(
                        'SIMPAN PENGATURAN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
