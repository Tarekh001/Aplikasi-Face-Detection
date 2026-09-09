/// Model for the predict API response.
///
/// Backend returns on success (200):
/// ```json
/// {
///   "nip": "123456789012345678",
///   "name": "Nama Pegawai",
///   "status": "Presensi IN Berhasil",
///   "status_kehadiran": "ON_TIME" | "LATE",
///   "keterlambatan_menit": 0,
///   "waktu": "08:00:15"
/// }
/// ```
///
/// Backend returns on unknown face (200 with nip=unknown):
/// ```json
/// { "nip": "unknown", "name": "unknown", "similarity": 0.45 }
/// ```
class PredictResponse {
  final String nip;
  final String name;
  final String status;
  final String statusKehadiran;
  final int keterlambatanMenit;
  final String waktu;

  PredictResponse({
    required this.nip,
    required this.name,
    required this.status,
    required this.statusKehadiran,
    required this.keterlambatanMenit,
    required this.waktu,
  });

  factory PredictResponse.fromJson(Map<String, dynamic> json) {
    return PredictResponse(
      nip: json['nip']?.toString() ?? 'unknown',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusKehadiran: json['status_kehadiran']?.toString() ?? '',
      keterlambatanMenit: int.tryParse(json['keterlambatan_menit']?.toString() ?? '0') ?? 0,
      waktu: json['waktu']?.toString() ?? '',
    );
  }

  bool get isUnknown => nip == 'unknown';
  bool get isOnTime => statusKehadiran == 'ON_TIME';
  bool get isLate => statusKehadiran == 'LATE';

  /// Detects session type from the status string (e.g. "Presensi IN Berhasil")
  String get tipeAbsen {
    if (status.contains('IN')) return 'IN';
    if (status.contains('OUT')) return 'OUT';
    return '';
  }
}
