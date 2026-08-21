import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? response;

  const ApiException(
    this.message, {
    this.statusCode,
    this.response,
  });

  bool get isUnauthorized => statusCode == 401;

  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();

  static const String baseUrl =
      'http://127.0.0.1/document_api_standard';

  static const Duration requestTimeout =
      Duration(seconds: 30);

  static final http.Client _client =
      http.Client();

  static String? _token;
  static DateTime? _expiresAt;

  static bool get isLoggedIn {
    final token = _token;

    if (token == null || token.isEmpty) {
      return false;
    }

    final expiresAt = _expiresAt;

    if (expiresAt != null &&
        DateTime.now().isAfter(expiresAt)) {
      clearSession();
      return false;
    }

    return true;
  }

  static String? get currentToken => _token;

  static void setSession({
    required String token,
    String? expiresAt,
  }) {
    final cleanToken = token.trim();

    if (cleanToken.isEmpty) {
      throw const ApiException(
        'رمز جلسة الدخول غير صحيح.',
      );
    }

    _token = cleanToken;

    _expiresAt = expiresAt == null
        ? null
        : DateTime.tryParse(expiresAt);
  }

  static void clearSession() {
    _token = null;
    _expiresAt = null;
  }

  static Uri _buildUri(
    String endpoint, [
    Map<String, dynamic>? queryParameters,
  ]) {
    final cleanEndpoint = endpoint
        .trim()
        .replaceFirst(
          RegExp(r'^/+'),
          '',
        );

    final uri = Uri.parse(
      '$baseUrl/$cleanEndpoint',
    );

    if (queryParameters == null ||
        queryParameters.isEmpty) {
      return uri;
    }

    final cleanQuery = <String, String>{};

    queryParameters.forEach((key, value) {
      if (value != null) {
        cleanQuery[key] = value.toString();
      }
    });

    return uri.replace(
      queryParameters: cleanQuery,
    );
  }

  static Map<String, String> _headers({
    required bool authenticated,
    bool jsonContent = false,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (jsonContent)
        'Content-Type':
            'application/json; charset=UTF-8',
    };

    if (authenticated) {
      final token = _token;

      if (token == null || token.isEmpty) {
        throw const ApiException(
          'يجب تسجيل الدخول أولًا.',
          statusCode: 401,
        );
      }

      headers['Authorization'] =
          'Bearer $token';
    }

    return headers;
  }

  static Map<String, dynamic> _decodeJson(
    http.Response response,
  ) {
    if (response.bodyBytes.isEmpty) {
      throw ApiException(
        'لم يرسل الخادم استجابة.',
        statusCode: response.statusCode,
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(
        utf8.decode(
          response.bodyBytes,
          allowMalformed: false,
        ),
      );
    } on FormatException {
      throw ApiException(
        'استجابة الخادم غير صحيحة.',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map) {
      throw ApiException(
        'صيغة استجابة الخادم غير صحيحة.',
        statusCode: response.statusCode,
      );
    }

    return Map<String, dynamic>.from(
      decoded,
    );
  }

  static Map<String, dynamic> _handleJsonResponse(
    http.Response response,
  ) {
    final data = _decodeJson(response);

    final success =
        data['success'] == true;

    if (response.statusCode == 401) {
      clearSession();
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !success) {
      throw ApiException(
        data['message']?.toString() ??
            'تعذر تنفيذ العملية.',
        statusCode: response.statusCode,
        response: data,
      );
    }

    return data;
  }

  static Future<Map<String, dynamic>> getJson(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    try {
      final response = await _client
          .get(
            _buildUri(
              endpoint,
              queryParameters,
            ),
            headers: _headers(
              authenticated: authenticated,
            ),
          )
          .timeout(requestTimeout);

      return _handleJsonResponse(response);
    } on TimeoutException {
      throw const ApiException(
        'انتهت مهلة الاتصال بالخادم.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'تعذر الاتصال بخادم الأرشفة.',
      );
    }
  }

  static Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    try {
      final response = await _client
          .post(
            _buildUri(endpoint),
            headers: _headers(
              authenticated: authenticated,
              jsonContent: true,
            ),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);

      return _handleJsonResponse(response);
    } on TimeoutException {
      throw const ApiException(
        'انتهت مهلة الاتصال بالخادم.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'تعذر الاتصال بخادم الأرشفة.',
      );
    }
  }

  static Future<Uint8List> getPdfBytes({
    required int id,
    required String recordType,
  }) async {
    if (id < 1) {
      throw const ApiException(
        'معرّف الملف غير صحيح.',
      );
    }

    if (recordType != 'main' &&
        recordType != 'attachment') {
      throw const ApiException(
        'نوع الملف غير صحيح.',
      );
    }

    try {
      final response = await _client
          .get(
            _buildUri(
              'open_pdf.php',
              {
                'id': id,
                'record_type': recordType,
              },
            ),
            headers: {
              ..._headers(
                authenticated: true,
              ),
              'Accept': 'application/pdf',
            },
          )
          .timeout(
            const Duration(minutes: 2),
          );

      if (response.statusCode == 401) {
        clearSession();

        throw const ApiException(
          'انتهت جلسة الدخول.',
          statusCode: 401,
        );
      }

      final contentType =
          response.headers['content-type']
              ?.toLowerCase();

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          contentType == null ||
          !contentType.contains(
            'application/pdf',
          )) {
        Map<String, dynamic>? errorData;

        try {
          errorData = _decodeJson(response);
        } catch (_) {
          errorData = null;
        }

        throw ApiException(
          errorData?['message']?.toString() ??
              'تعذر فتح ملف PDF.',
          statusCode: response.statusCode,
          response: errorData,
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw const ApiException(
          'ملف PDF فارغ.',
        );
      }

      return response.bodyBytes;
    } on TimeoutException {
      throw const ApiException(
        'استغرق فتح ملف PDF وقتًا طويلًا.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'تعذر الاتصال بخادم الأرشفة.',
      );
    }
  }

  static void close() {
    _client.close();
    clearSession();
  }
}