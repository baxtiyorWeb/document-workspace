class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => message;
}

class ApiException extends AppException {
  final int statusCode;

  const ApiException(super.message, {required this.statusCode, super.code});
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

class NetworkException extends AppException {
  const NetworkException([
    super.message = 'Tarmoq bilan aloqa yo\'q. Internetni tekshiring.',
  ]) : super(code: 'NETWORK_ERROR');
}

class CancelledException extends AppException {
  const CancelledException([super.message = 'Amal bekor qilindi'])
    : super(code: 'CANCELLED');
}
