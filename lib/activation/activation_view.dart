import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/api_error.dart';

/// Activation/Binding screen — Admin login + automated device binding.
///
/// Flow:
///   1. Admin set Server URL (jika belum), masukkan Username + Password
///   2. Taps "Aktivasi Perangkat"
///   3. App login via POST /api/login → dapat JWT token
///   4. App OTOMATIS collect device SN (Android ID) + model via device_info_plus
///   5. App call POST /api/devices/bind dengan JWT
///   6. Sukses → simpan is_bound=true → navigate ke home
class ActivationView extends StatefulWidget {
  final VoidCallback onBound;

  const ActivationView({super.key, required this.onBound});

  @override
  State<ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<ActivationView> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showServerUrl = false;
  String _statusMessage = '';
  String _detectedDeviceId = '...';

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _detectDeviceId();
  }

  Future<void> _loadDefaults() async {
    final baseUrl = await AppConfig.getBaseUrl();
    _serverUrlController.text = baseUrl;
  }

  /// Detect device ID automatically on screen load
  Future<void> _detectDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = 'Unknown';

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id; // Android ID (unique per device)
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor ?? 'Unknown';
    }

    if (mounted) {
      setState(() => _detectedDeviceId = deviceId);
    }
  }

  /// Collect device metadata OTOMATIS via device_info_plus
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceSn = 'Unknown';
    String deviceName = 'Unknown';
    String platform = 'Unknown';

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceSn = info.id; // Android ID = SN otomatis
      deviceName = '${info.brand} ${info.model}';
      platform = 'Android ${info.version.release}';
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceSn = info.identifierForVendor ?? 'Unknown';
      deviceName = info.utsname.machine;
      platform = 'iOS ${info.systemVersion}';
    }

    // Collect IP address
    String ipAddress = '';
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ipAddress = addr.address;
            break;
          }
        }
        if (ipAddress.isNotEmpty) break;
      }
    } catch (_) {}

    return {
      'device_sn': deviceSn,
      'device_name': deviceName,
      'platform': platform,
      'ip_address': ipAddress.isNotEmpty ? ipAddress : null,
      'nama_lokasi': 'Kiosk Mobile',
    };
  }

  Future<void> _handleActivate() async {
    final serverUrl = _serverUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _statusMessage = '❌ Server URL, Username, dan Password wajib diisi');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '⏳ Menyimpan konfigurasi...';
    });

    try {
      // 1. Simpan server URL
      await AppConfig.setBaseUrl(serverUrl);

      // 2. Login untuk mendapatkan JWT token
      setState(() => _statusMessage = '⏳ Login sebagai Admin...');
      final loginResult = await ApiService.loginAdmin(username, password);
      final token = loginResult['access_token'] as String;
      final adminName = loginResult['user']?['nama'] ?? username;

      // 3. Kumpulkan info device OTOMATIS
      setState(() => _statusMessage = '⏳ Mengidentifikasi perangkat...');
      final deviceInfo = await _collectDeviceInfo();

      // 4. Simpan SN otomatis ke config
      await AppConfig.setDeviceSn(deviceInfo['device_sn']);

      // 5. Bind device ke OPD admin
      setState(() => _statusMessage = '⏳ Mengikat perangkat ke instansi...');
      final bindResult = await ApiService.bindDevice(token, deviceInfo);

      // 6. Simpan status binding
      await AppConfig.setIsBound(true);
      await AppConfig.setBoundOpdName(
        bindResult['opd_name'] ?? 'OPD ID ${bindResult['opd_id']}',
      );

      final opdName = bindResult['opd_name'] ?? '-';
      setState(() => _statusMessage = '✅ Berhasil! Perangkat terikat ke $opdName oleh $adminName');

      // Short delay then navigate
      await Future.delayed(const Duration(seconds: 1));
      widget.onBound();
    } on ApiError catch (e) {
      setState(() => _statusMessage = '❌ ${e.error}');
    } catch (e) {
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktivasi Perangkat'),
        actions: [
          // Toggle server URL visibility
          IconButton(
            icon: Icon(_showServerUrl ? Icons.dns : Icons.dns_outlined),
            tooltip: 'Setting IP Server',
            onPressed: () => setState(() => _showServerUrl = !_showServerUrl),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Perangkat ini belum terdaftar.\nLogin sebagai Admin untuk mengikat perangkat ke instansi.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            // --- Device Info Card (Read-only) ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smartphone, color: Colors.blue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Device ID (Otomatis)',
                            style: TextStyle(fontSize: 11, color: Colors.blue)),
                        Text(_detectedDeviceId,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- Server URL (collapsible) ---
            if (_showServerUrl) ...[
              const Text('Koneksi Server',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://192.168.x.x:5000',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // --- Login Admin ---
            const Text('Login Admin',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),

            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username / NIP',
                hintText: 'admin001@kabtangerang.go.id',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleActivate,
              icon: _isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(_isLoading ? 'Memproses...' : 'Aktivasi Perangkat'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.startsWith('✅')
                      ? Colors.green.withAlpha(25)
                      : _statusMessage.startsWith('❌')
                          ? Colors.red.withAlpha(25)
                          : Colors.grey.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _statusMessage.startsWith('✅')
                        ? Colors.green[800]
                        : _statusMessage.startsWith('❌')
                            ? Colors.red[800]
                            : Colors.grey[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
