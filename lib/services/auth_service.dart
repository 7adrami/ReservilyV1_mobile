import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../models/user.dart';

/// Authentication endpoints: login, signup (with OTP), password reset/change
/// and profile updates. Also handles restoring a stored session on startup.
class AuthService extends ChangeNotifier {
  AuthService({required this.api, required this.session, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    session.addListener(_onSessionChanged);
  }

  final ApiClient api;
  final Session session;
  final FlutterSecureStorage _storage;

  void _onSessionChanged() => notifyListeners();

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  static const _kUserId = 'reservily_user_id';
  static const _kUserJson = 'reservily_user_json';

  /// Restore a previously stored session from secure storage.
  Future<bool> restore() async {
    try {
      final raw = await _storage.read(key: _kUserJson);
      final id = await _storage.read(key: _kUserId);
      if (raw == null || id == null) {
        session.setRestoring(false);
        return false;
      }
      final user = User.fromJson(_decodeMap(raw));
      session.setUser(user);
      // Keep the profile fresh (also validates the token).
      try {
        final data = await api.request('/api/auth/me/');
        session.setUser(User.fromJson(data as Map<String, dynamic>));
        await _storeUser(User.fromJson(data));
      } on Exception {
        // Token expired and refresh failed: drop the session.
        await api.clearTokens();
        session.logout();
        return false;
      }
      return true;
    } catch (_) {
      session.setRestoring(false);
      return false;
    }
  }

  Future<void> login(String username, String password) async {
    final data = await api.request(
      '/api/auth/login/',
      method: 'POST',
      body: {'username': username, 'password': password},
    ) as Map<String, dynamic>;
    await _applyLogin(data);
  }

  /// Sends a signup code. Returns the OTP code in development (console email
  /// backend) so it can be shown inline; null in production.
  Future<String?> signupSend(String username, String email) async {
    final data = await api.request(
      '/api/auth/signup/',
      method: 'POST',
      body: {'username': username, 'email': email},
    ) as Map<String, dynamic>;
    return data['debug_code'] as String?;
  }

  Future<void> signupComplete({
    required String username,
    required String email,
    required String code,
    required String password1,
    required String password2,
    String? firstName,
    String? lastName,
  }) async {
    final data = await api.request(
      '/api/auth/signup/complete/',
      method: 'POST',
      body: {
        'username': username,
        'email': email,
        'code': code,
        'password1': password1,
        'password2': password2,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    ) as Map<String, dynamic>;
    await _applyLogin(data);
  }

  Future<String?> passwordResetSend(String email) async {
    final data = await api.request(
      '/api/auth/password/reset/',
      method: 'POST',
      body: {'email': email},
    ) as Map<String, dynamic>;
    return data['debug_code'] as String?;
  }

  Future<void> passwordResetComplete({
    required String email,
    required String code,
    required String password1,
    required String password2,
  }) async {
    final data = await api.request(
      '/api/auth/password/reset/complete/',
      method: 'POST',
      body: {
        'email': email,
        'code': code,
        'password1': password1,
        'password2': password2,
      },
    ) as Map<String, dynamic>;
    await _applyLogin(data);
  }

  Future<String?> passwordChangeSend() async {
    final data = await api.request(
        '/api/auth/password/change/', method: 'POST') as Map<String, dynamic>;
    return data['debug_code'] as String?;
  }

  Future<void> passwordChangeComplete({
    required String code,
    required String password1,
    required String password2,
  }) async {
    await api.request(
      '/api/auth/password/change/complete/',
      method: 'POST',
      body: {'code': code, 'password1': password1, 'password2': password2},
    );
  }

  Future<String?> emailChangeSend(String newEmail) async {
    final data = await api.request(
      '/api/auth/email/change/',
      method: 'POST',
      body: {'new_email': newEmail},
    ) as Map<String, dynamic>;
    return data['debug_code'] as String?;
  }

  Future<void> emailChangeComplete(String newEmail, String code) async {
    await api.request(
      '/api/auth/email/change/complete/',
      method: 'POST',
      body: {'new_email': newEmail, 'code': code},
    );
  }

  Future<User> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    bool? waitingListVisible,
  }) async {
    final body = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (waitingListVisible != null) 'waiting_list_visible': waitingListVisible,
    };
    final data = await api.request(
      '/api/auth/me/',
      method: 'PATCH',
      body: body,
    ) as Map<String, dynamic>;
    final user = User.fromJson(data);
    session.setUser(user);
    await _storeUser(user);
    return user;
  }

  Future<void> uploadAvatarBytes(List<int> bytes, String filename) async {
    final data = await api.upload(
      '/api/auth/me/',
      file: MultipartFile.fromBytes(bytes, filename: filename),
      fileField: 'avatar',
    ) as Map<String, dynamic>;
    final user = User.fromJson(data);
    session.setUser(user);
    await _storeUser(user);
  }

  Future<void> logout() async {
    await api.clearTokens();
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUserJson);
    session.logout();
  }

  Future<void> _applyLogin(Map<String, dynamic> data) async {
    final access = data['access'] as String;
    final refresh = data['refresh'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await api.saveTokens(access, refresh);
    await _storeUser(user);
    session.setUser(user);
  }

  Future<void> _storeUser(User user) async {
    await _storage.write(key: _kUserId, value: '${user.id}');
    await _storage.write(key: _kUserJson, value: jsonEncode(_map(user)));
  }

  Map<String, dynamic> _map(User u) => {
        'id': u.id,
        'username': u.username,
        'name': u.name,
        'first_name': u.firstName,
        'last_name': u.lastName,
        'role': u.role,
        'email': u.email,
        'phone': u.phone,
        'avatar': u.avatar,
        'waiting_list_visible': u.waitingListVisible,
        'has_key': u.hasKey,
        'owned_shop_slug': u.ownedShopSlug,
      };

  Map<String, dynamic> _decodeMap(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;
}
