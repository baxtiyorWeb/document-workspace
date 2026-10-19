import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';

class ApiClient {
  final String Function() getBaseUrl;
  final String? Function() getAccessToken;
  final http.Client _client;

  ApiClient({
    required this.getBaseUrl,
    required this.getAccessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = getAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final base = getBaseUrl().replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$cleanPath').replace(queryParameters: queryParams);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParams}) async {
    try {
      final uri = _buildUri(path, queryParams);
      final resp = await _client.get(uri, headers: _buildHeaders());
      return _processResponse(resp);
    } on SocketException {
      throw const NetworkException();
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('So\'rov bajarishda xatolik: $e');
    }
  }

  Future<dynamic> post(String path, {dynamic body}) async {
    try {
      final uri = _buildUri(path);
      final resp = await _client.post(
        uri,
        headers: _buildHeaders(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(resp);
    } on SocketException {
      throw const NetworkException();
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('So\'rov bajarishda xatolik: $e');
    }
  }

  Future<dynamic> patch(String path, {dynamic body}) async {
    try {
      final uri = _buildUri(path);
      final resp = await _client.patch(
        uri,
        headers: _buildHeaders(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(resp);
    } on SocketException {
      throw const NetworkException();
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('So\'rov bajarishda xatolik: $e');
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final uri = _buildUri(path);
      final resp = await _client.delete(uri, headers: _buildHeaders());
      return _processResponse(resp);
    } on SocketException {
      throw const NetworkException();
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('So\'rov bajarishda xatolik: $e');
    }
  }

  Future<dynamic> uploadFile(
    String path, {
    required String filePath,
    String fieldName = 'file',
    Map<String, String>? fields,
  }) async {
    try {
      final uri = _buildUri(path);
      final request = http.MultipartRequest('POST', uri);
      final token = getAccessToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';
      if (fields != null) {
        request.fields.addAll(fields);
      }
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _processResponse(response);
    } on SocketException {
      throw const NetworkException();
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Faylni yuklashda xatolik: $e');
    }
  }

  dynamic _processResponse(http.Response response) {
    dynamic jsonBody;
    try {
      if (response.body.isNotEmpty) {
        jsonBody = jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (jsonBody is Map<String, dynamic> && jsonBody.containsKey('data')) {
        return jsonBody['data'];
      }
      return jsonBody;
    }

    String message = 'Server xatosi (${response.statusCode})';
    String? code;

    if (jsonBody is Map<String, dynamic> && jsonBody.containsKey('error')) {
      final err = jsonBody['error'];
      if (err is Map<String, dynamic>) {
        message = err['message'] ?? message;
        code = err['code'];
      }
    }

    if (response.statusCode == 401) {
      throw AuthException(message, code: code);
    }

    throw ApiException(message, statusCode: response.statusCode, code: code);
  }
}
