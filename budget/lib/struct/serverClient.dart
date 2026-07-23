import 'dart:convert';

import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ServerClient {
  static String get _baseUrl {
    final configured = (appStateSettings["serverUrl"] ?? "").trim();
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) {
      try {
        return Uri.base.origin;
      } catch (_) {
        return "";
      }
    }
    return "";
  }

  static String get _token => appStateSettings["serverToken"] ?? "";

  static bool get isConfigured => _baseUrl.isNotEmpty;

  static void _ensureConfigured() {
    if (_baseUrl.isEmpty) {
      throw ServerException("Server URL is not configured", 0);
    }
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || (!uri.isScheme("http") && !uri.isScheme("https"))) {
      throw ServerException("Invalid server URL", 0);
    }
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  static Map<String, String> get _multipartHeaders => {
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  static Future<Map<String, dynamic>> get(String path) async {
    _ensureConfigured();
    final response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body}) async {
    _ensureConfigured();
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: body != null ? json.encode(body) : null,
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    _ensureConfigured();
    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  static Future<http.Response> getRaw(String path) async {
    _ensureConfigured();
    return await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    );
  }

  static Future<Map<String, dynamic>> uploadFile(
      String path, String filePath, String fieldName,
      {Map<String, String>? fields}) async {
    _ensureConfigured();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$path'),
    );
    request.headers.addAll(_multipartHeaders);
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    fields?.forEach((key, value) => request.fields[key] = value);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  static Future<http.Response> downloadFile(String path) async {
    _ensureConfigured();
    return await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    );
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body);
    }
    if (response.statusCode == 401) {
      throw ServerAuthException('Unauthorized');
    }
    String message = 'Request failed (${response.statusCode})';
    try {
      final body = json.decode(response.body);
      if (body['error'] != null) message = body['error'];
    } catch (_) {}
    throw ServerException(message, response.statusCode);
  }

  static Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        return body['status'] == 'ok';
      }
    } catch (_) {}
    return false;
  }
}

class ServerException implements Exception {
  final String message;
  final int statusCode;
  ServerException(this.message, this.statusCode);

  @override
  String toString() => message;
}

class ServerAuthException implements Exception {
  final String message;
  ServerAuthException(this.message);

  @override
  String toString() => message;
}
