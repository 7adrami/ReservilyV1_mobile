import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_exception.dart';
import 'constants.dart';

/// Thin wrapper around [Dio] that:
///  - attaches the JWT access token to every request,
///  - transparently refreshes the access token when it expires,
///  - maps Django/DRF error payloads to [ApiException].
class ApiClient {
  ApiClient({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _readAccess();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          if (status == 401 &&
              !error.requestOptions.path.contains('/auth/refresh/') &&
              await _refresh()) {
            return handler.resolve(await _retry(error.requestOptions));
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;
  final FlutterSecureStorage _storage;
  bool _refreshing = false;

  static const _kAccess = 'reservily_access';
  static const _kRefresh = 'reservily_refresh';

  Future<String?> _readAccess() => _storage.read(key: _kAccess);
  Future<String?> _readRefresh() => _storage.read(key: _kRefresh);

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<bool> _refresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = await _readRefresh();
      if (refresh == null || refresh.isEmpty) return false;
      final resp = await Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          headers: {'Accept': 'application/json'},
        ),
      ).post(
        '/api/auth/refresh/',
        data: {'refresh': refresh},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final access = resp.data['access'] as String;
      await _storage.write(key: _kAccess, value: access);
      return true;
    } catch (_) {
      await clearTokens();
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<Response> _retry(RequestOptions options) {
    return _dio.request(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      options: Options(
        method: options.method,
        headers: options.headers,
        contentType: options.contentType,
      ),
    );
  }

  /// Performs a request and decodes JSON, throwing [ApiException] on failure.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    dynamic body,
    bool form = false,
  }) async {
    try {
      final response = await _dio.request(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: form ? Headers.multipartFormDataContentType : Headers.jsonContentType,
          responseType: ResponseType.json,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Multipart upload (payment proof, chat media, photos).
  Future<dynamic> upload(
    String path, {
    Map<String, dynamic>? fields,
    MultipartFile? file,
    String? fileField,
  }) async {
    final form = FormData();
    if (fields != null) fields.forEach((k, v) => form.fields.add(MapEntry(k, '$v')));
    if (file != null && fileField != null) form.files.add(MapEntry(fileField, file));
    try {
      final response = await _dio.post(
        path,
        data: form,
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          responseType: ResponseType.json,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Downloads raw bytes (used for encrypted chat media).
  Future<List<int>> download(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException(
        'Cannot reach the server at ${AppConfig.baseUrl}. Is the Django '
        'server running and is the device on the same network?',
        statusCode: e.response?.statusCode,
      );
    }
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is String) return ApiException(error, statusCode: e.response?.statusCode);
      final detail = data['detail'];
      if (detail is String) return ApiException(detail, statusCode: e.response?.statusCode);
    }
    return ApiException(
      e.message ?? 'Request failed',
      statusCode: e.response?.statusCode,
    );
  }
}
