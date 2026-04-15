/// Model for successful predict API response.
///
/// Backend returns:
/// ```json
/// { "status": "ON_TIME" | "LATE", "waktu": "HH:MM:SS", "name": "Nama Pegawai" }
/// ```
class PredictResponse {
  final String status;
  final String waktu;
  final String name;

  PredictResponse({
    required this.status,
    required this.waktu,
    required this.name,
  });

  factory PredictResponse.fromJson(Map<String, dynamic> json) {
    return PredictResponse(
      status: json['status']?.toString() ?? '',
      waktu: json['waktu']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  bool get isOnTime => status == 'ON_TIME';
  bool get isLate => status == 'LATE';
}
