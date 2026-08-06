/// A structured error surfaced from the Reservily API.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fieldErrors;

  @override
  String toString() => message;
}
