import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SSEEvent {
  final String event;
  final Map<String, dynamic> data;

  const SSEEvent({required this.event, required this.data});

  @override
  String toString() => 'SSEEvent(event: $event, data: $data)';
}

class SSEClient {
  http.Client? _activeClient;

  Stream<SSEEvent> streamGeneration({
    required Uri uri,
    required Map<String, dynamic> body,
    required String? token,
  }) async* {
    _activeClient = http.Client();
    final client = _activeClient!;

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.body = jsonEncode(body);

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await client.send(request);
    } catch (e) {
      throw Exception('Serverga ulanib bo\'lmadi: $e');
    }

    if (streamedResponse.statusCode != 200) {
      final bodyStr = await streamedResponse.stream.bytesToString();
      try {
        final errJson = jsonDecode(bodyStr);
        if (errJson is Map && errJson.containsKey('error')) {
          throw Exception(errJson['error']['message'] ?? 'Generatsiya xatosi');
        }
      } catch (_) {}
      throw Exception('Server xatosi: HTTP ${streamedResponse.statusCode}');
    }

    String currentEvent = 'message';
    final buffer = StringBuffer();

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final raw = buffer.toString();
      final lines = raw.split('\n');

      // The last line might be incomplete, preserve it in buffer
      buffer.clear();
      buffer.write(lines.last);

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final dataStr = line.substring(5).trim();
          try {
            final parsed = jsonDecode(dataStr);
            if (parsed is Map<String, dynamic>) {
              yield SSEEvent(event: currentEvent, data: parsed);
            }
          } catch (_) {}
        }
      }
    }
  }

  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }
}
