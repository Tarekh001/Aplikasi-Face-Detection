import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Offline-Ready Store-and-Forward Service.
///
/// Jika kiosk kehilangan koneksi internet saat presensi:
/// 1. Foto disalin ke direktori persisten (bukan temp)
/// 2. Payload (foto path, device_sn, timestamp) disimpan ke SharedPreferences
/// 3. Saat koneksi pulih, semua pending records dikirim ulang ke backend
///    dengan `local_timestamp` agar waktu presensi akurat
class OfflineSyncService {
  static const String _pendingKey = 'pending_attendance';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));

  // ═══════════════════════════════════════════
  // STORE — Simpan payload ke local storage
  // ═══════════════════════════════════════════

  /// Simpan presensi yang gagal dikirim ke antrian offline.
  /// [photoFile] akan disalin ke direktori persisten agar tidak terhapus.
  /// [localTimestamp] adalah waktu TEPAT saat ASN scan wajah (DateTime.now()).
  static Future<void> storePendingAttendance({
    required File photoFile,
    required String localTimestamp,
  }) async {
    try {
      // 1. Salin foto ke direktori persisten (temp bisa terhapus kapan saja)
      final appDir = await getApplicationDocumentsDirectory();
      final offlineDir = Directory('${appDir.path}/offline_queue');
      if (!await offlineDir.exists()) {
        await offlineDir.create(recursive: true);
      }

      final fileName = 'offline_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final persistedPhoto = await photoFile.copy('${offlineDir.path}/$fileName');

      // 2. Buat record
      final deviceSn = await AppConfig.getDeviceSn();
      final record = {
        'photo_path': persistedPhoto.path,
        'device_sn': deviceSn,
        'local_timestamp': localTimestamp,
        'created_at': DateTime.now().toIso8601String(),
      };

      // 3. Tambahkan ke antrian di SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final List<String> queue = prefs.getStringList(_pendingKey) ?? [];
      queue.add(jsonEncode(record));
      await prefs.setStringList(_pendingKey, queue);

      debugPrint('📶 [Offline] Stored pending attendance '
          '(queue size: ${queue.length}, time: $localTimestamp)');
    } catch (e) {
      debugPrint('❌ [Offline] Failed to store: $e');
    }
  }

  /// Jumlah presensi yang menunggu sinkronisasi.
  static Future<int> getPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingKey) ?? []).length;
  }

  // ═══════════════════════════════════════════
  // FORWARD — Kirim semua pending ke backend
  // ═══════════════════════════════════════════

  /// Sinkronkan semua presensi offline ke backend.
  /// Dipanggil saat: app startup, kembali ke home screen, atau periodic timer.
  ///
  /// Returns jumlah record yang berhasil disinkronkan.
  static Future<int> syncPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> queue = prefs.getStringList(_pendingKey) ?? [];

    if (queue.isEmpty) return 0;

    debugPrint('📶 [Offline-Sync] Starting sync of ${queue.length} pending records...');

    final String baseUrl = await AppConfig.getBaseUrl();
    final String predictUrl = '$baseUrl${AppConfig.predictEndpoint}';

    int syncedCount = 0;
    final List<String> remainingQueue = [];

    for (final recordJson in queue) {
      try {
        final record = jsonDecode(recordJson) as Map<String, dynamic>;
        final photoPath = record['photo_path'] as String;
        final deviceSn = record['device_sn'] as String;
        final localTimestamp = record['local_timestamp'] as String;

        // Cek apakah file foto masih ada
        final photoFile = File(photoPath);
        if (!await photoFile.exists()) {
          debugPrint('⚠️ [Offline-Sync] Photo missing, skipping: $photoPath');
          // Hapus dari queue (file hilang, tidak bisa di-retry)
          continue;
        }

        // Kirim ke backend dengan local_timestamp
        final formData = FormData.fromMap({
          'photo': await MultipartFile.fromFile(
            photoPath,
            filename: basename(photoPath),
          ),
          'device_sn': deviceSn,
          'local_timestamp': localTimestamp,
        });

        final response = await _dio.post(predictUrl, data: formData);

        if (response.statusCode == 200) {
          syncedCount++;
          debugPrint('✅ [Offline-Sync] Synced: $localTimestamp');

          // Hapus file foto setelah berhasil
          try { await photoFile.delete(); } catch (_) {}
        } else {
          // Server menolak (400/403/401) — jangan retry, buang
          final errMsg = response.data?['error'] ?? response.data?['message'] ?? 'Unknown';
          debugPrint('⚠️ [Offline-Sync] Server rejected ($errMsg), removing from queue');

          try { await photoFile.delete(); } catch (_) {}
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          // Masih offline — simpan kembali ke queue, stop sync
          debugPrint('📶 [Offline-Sync] Still offline, keeping remaining in queue');
          remainingQueue.add(recordJson);
          // Tambahkan sisa yang belum diproses
          final currentIdx = queue.indexOf(recordJson);
          if (currentIdx >= 0) {
            for (int i = currentIdx + 1; i < queue.length; i++) {
              remainingQueue.add(queue[i]);
            }
          }
          break;
        } else {
          // Error lain — skip record ini
          debugPrint('⚠️ [Offline-Sync] Error: ${e.message}, skipping record');
        }
      } catch (e) {
        debugPrint('❌ [Offline-Sync] Unexpected error: $e');
        remainingQueue.add(recordJson);
      }
    }

    // Update queue di SharedPreferences
    await prefs.setStringList(_pendingKey, remainingQueue);

    if (syncedCount > 0) {
      debugPrint('📶 [Offline-Sync] Done! Synced: $syncedCount, '
          'remaining: ${remainingQueue.length}');
    }

    return syncedCount;
  }

  /// Cek apakah server bisa dijangkau (simple connectivity check).
  static Future<bool> isServerReachable() async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      // Lightweight HEAD request atau timeout pendek
      await _dio.get(
        '$baseUrl/api/check-spoof',
        options: Options(
          method: 'HEAD',
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
