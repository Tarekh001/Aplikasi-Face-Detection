/// Structured error model for API error responses.
///
/// Maps HTTP status codes to user-friendly Indonesian messages:
/// - 400 → "Foto tidak valid atau tidak ditemukan"
/// - 403 → "Wajah tidak dikenali"
/// - 500 → "Terjadi kesalahan pada server"
class ApiError {
  final String error;
  final int statusCode;

  ApiError({
    required this.error,
    required this.statusCode,
  });

  factory ApiError.fromStatusCode(int statusCode, {String? serverMessage}) {
    String message;
    switch (statusCode) {
      case 400:
        message = serverMessage ?? 'Foto tidak valid atau tidak ditemukan';
        break;
      case 403:
        message = serverMessage ?? 'Wajah tidak dikenali';
        break;
      case 404:
        message = serverMessage ?? 'Endpoint tidak ditemukan';
        break;
      case 500:
        message = serverMessage ?? 'Terjadi kesalahan pada server';
        break;
      default:
        message = serverMessage ?? 'Terjadi kesalahan (kode: $statusCode)';
    }
    return ApiError(error: message, statusCode: statusCode);
  }

  factory ApiError.fromException(String message) {
    return ApiError(error: message, statusCode: 0);
  }

  @override
  String toString() => 'ApiError($statusCode): $error';
}
