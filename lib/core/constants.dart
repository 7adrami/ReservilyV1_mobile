import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Central app-wide constants and configuration.
class AppConfig {
  AppConfig._();

  /// Override at build time: `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
  static const String _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// The Django server address the app talks to.
  ///
  /// On Android emulators the host machine is reached via 10.0.2.2; on iOS
  /// simulators plain localhost works; a real phone needs your PC's LAN IP,
  /// passed with --dart-define=API_BASE_URL=...
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// Chat encryption parameters (must match the web app exactly).
  static const String saltInfo = 'reservily-chat-v1';
  static const int kekIterations = 150000;
  static const int kekSaltBytes = 16;
  static const int aesIvBytes = 12;

  static const List<String> reactEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  static const String currency = 'UM';
}
