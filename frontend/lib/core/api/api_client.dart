import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth_state.dart';

/// Extract the `detail` field from a FastAPI error response.
/// Handles: Map, JSON-encoded String, or bare String.
String extractApiError(DioException e, String fallback) {
  final data = e.response?.data;
  if (data == null) return fallback;

  // Parsed JSON → Map
  if (data is Map) {
    final detail = data['detail'];
    if (detail != null && detail.toString().isNotEmpty) return detail.toString();
    return fallback;
  }

  // Unparsed JSON string (rare but happens on some platforms)
  if (data is String && data.isNotEmpty) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail != null && detail.toString().isNotEmpty) return detail.toString();
      }
    } catch (_) {}
    return fallback;
  }

  return fallback;
}

const _productionHost = 'backend-shopho-production.up.railway.app';
const _isDev = bool.fromEnvironment('FLUTTER_DEV', defaultValue: false);

const apiBaseUrl = _isDev
    ? 'http://192.168.100.195:8000/api/v1'
    : 'https://$_productionHost/api/v1';
const wsBaseUrl = _isDev
    ? 'ws://192.168.100.195:8000/api/v1'
    : 'wss://$_productionHost/api/v1';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_storage, _dio),
      _CurlInterceptor(),
    ]);
  }

  Dio get dio => _dio;
}

class _CurlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final uri = options.uri.toString();

    final headerParts = options.headers.entries
        .map((e) => "-H '${e.key}: ${e.value}'")
        .join(' ');

    String dataPart = '';
    if (options.data != null) {
      try {
        if (options.data is FormData) {
          final fd = options.data as FormData;
          final fields = fd.fields.map((e) => '-F "${e.key}=${e.value}"').join(' ');
          final files = fd.files.map((e) => '-F "${e.key}=@<file>"').join(' ');
          dataPart = [fields, files].where((s) => s.isNotEmpty).join(' ');
        } else {
          final body = options.data is String
              ? options.data as String
              : jsonEncode(options.data);
          dataPart = "-d '${body.replaceAll("'", "\\'")}'";
        }
      } catch (_) {
        dataPart = '-d "<unencodable>"';
      }
    }

    final curl = "curl -X $method '$uri' $headerParts ${dataPart.trim()}".trim();
    debugPrint('[CURL] $curl');

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[CURL] ← ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final detail = (err.response?.data is Map) ? err.response?.data['detail'] : err.response?.data;
    debugPrint('[CURL] ← ${err.response?.statusCode ?? "ERR"} ${err.requestOptions.method} ${err.requestOptions.uri} — $detail');
    handler.next(err);
  }
}

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;

  _AuthInterceptor(this._storage, this._dio);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Try to refresh
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken != null) {
        try {
          final res = await _dio.post(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(headers: {}), // no auth header for refresh
          );
          final newAccess = res.data['access_token'] as String;
          final newRefresh = res.data['refresh_token'] as String;
          await _storage.write(key: 'access_token', value: newAccess);
          await _storage.write(key: 'refresh_token', value: newRefresh);

          // Retry original request
          err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
          final retried = await _dio.fetch(err.requestOptions);
          return handler.resolve(retried);
        } catch (_) {
          await _storage.deleteAll();
          authTokenNotifier.value = null; // forces GoRouter → /login
        }
      }
    }
    handler.next(err);
  }
}
