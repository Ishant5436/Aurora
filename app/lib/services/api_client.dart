import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

/// A failed API call, with a message that is safe to show the user.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  /// HTTP status, or 0 when the server could not be reached at all.
  final int status;
  final String code;
  final String message;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Thin JSON client for the Aurora backend.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.token})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String baseUrl;
  String? token;

  /// Invoked once when a request is rejected with 401. Return true after
  /// obtaining a fresh token and the request is retried.
  Future<bool> Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Duration timeout = _timeout,
    bool retryOnUnauthorized = true,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'timeout', 'The server took too long to answer. Please try again.');
    } on SocketException {
      throw const ApiException(0, 'network', 'Cannot reach the server. Check your connection.');
    } on http.ClientException {
      throw const ApiException(0, 'network', 'Cannot reach the server. Check your connection.');
    }

    if (response.statusCode == 401 && retryOnUnauthorized && onUnauthorized != null) {
      if (await onUnauthorized!()) {
        return _request(method, path, body: body, timeout: timeout, retryOnUnauthorized: false);
      }
    }

    Map<String, dynamic> json = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } on FormatException {
        // fall through: handled below by status code
      }
    }

    if (response.statusCode >= 400) {
      final error = json['error'];
      final message = error is Map ? error['message'] as String? : null;
      final code = error is Map ? error['code'] as String? : null;
      throw ApiException(
        response.statusCode,
        code ?? 'http_${response.statusCode}',
        message ?? 'Something went wrong (${response.statusCode}).',
      );
    }
    return json;
  }

  // Auth
  Future<Map<String, dynamic>> guestLogin(String deviceId) =>
      _request('POST', '/api/auth/guest', body: {'deviceId': deviceId}, retryOnUnauthorized: false);

  Future<Map<String, dynamic>> register(String email, String password, String? displayName) => _request(
        'POST',
        '/api/auth/register',
        body: {'email': email, 'password': password, if (displayName != null && displayName.isNotEmpty) 'displayName': displayName},
        retryOnUnauthorized: false,
      );

  Future<Map<String, dynamic>> login(String email, String password) => _request(
        'POST',
        '/api/auth/login',
        body: {'email': email, 'password': password},
        retryOnUnauthorized: false,
      );

  Future<Map<String, dynamic>> me() => _request('GET', '/api/auth/me');

  // Settings
  Future<Map<String, dynamic>> getSettings() => _request('GET', '/api/settings');
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> patch) =>
      _request('PUT', '/api/settings', body: patch);

  // Alarms
  Future<Map<String, dynamic>> listAlarms() => _request('GET', '/api/alarms');
  Future<Map<String, dynamic>> createAlarm(Map<String, dynamic> alarm) =>
      _request('POST', '/api/alarms', body: alarm);
  Future<Map<String, dynamic>> updateAlarm(String id, Map<String, dynamic> patch) =>
      _request('PATCH', '/api/alarms/$id', body: patch);
  Future<void> deleteAlarm(String id) => _request('DELETE', '/api/alarms/$id');

  // Notes
  Future<Map<String, dynamic>> listNotes() => _request('GET', '/api/notes');

  /// Sends pasted [text] or a [file] (base64) to be turned into a quiz. This
  /// calls the AI and can take a while, so it has a long timeout.
  Future<Map<String, dynamic>> uploadNote({
    String? title,
    String? text,
    String? fileName,
    String? mimeType,
    String? base64Data,
  }) =>
      _request(
        'POST',
        '/api/notes',
        timeout: const Duration(seconds: 150),
        body: {
          if (title != null && title.isNotEmpty) 'title': title,
          'text': ?text,
          if (base64Data != null)
            'file': {'name': fileName, 'mimeType': mimeType, 'base64': base64Data},
        },
      );

  Future<void> deleteNote(String id) => _request('DELETE', '/api/notes/$id');

  // Challenges
  Future<Map<String, dynamic>> startChallenge({String? alarmId, String? kind}) => _request(
        'POST',
        '/api/challenges/start',
        body: {'alarmId': ?alarmId, 'kind': ?kind},
      );

  Future<Map<String, dynamic>> answer(String sessionId, String questionId, int selected) => _request(
        'POST',
        '/api/challenges/$sessionId/answer',
        body: {'questionId': questionId, 'selected': selected},
      );

  Future<Map<String, dynamic>> submitVoice(String sessionId, int seconds, String base64Wav) => _request(
        'POST',
        '/api/challenges/$sessionId/voice',
        timeout: const Duration(seconds: 90),
        body: {
          'seconds': seconds,
          'audio': {'mimeType': 'audio/wav', 'base64': base64Wav},
        },
      );

  Future<Map<String, dynamic>> complete(String sessionId) =>
      _request('POST', '/api/challenges/$sessionId/complete', body: <String, dynamic>{});

  Future<void> abandon(String sessionId) =>
      _request('POST', '/api/challenges/$sessionId/abandon', body: <String, dynamic>{});
}
