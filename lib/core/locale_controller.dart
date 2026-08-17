import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's chosen UI language and notifies listeners on change.
class LocaleController extends ChangeNotifier {
  LocaleController() {
    _load();
  }

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const List<String> supported = ['en', 'fr', 'ar'];
  static const String _kKey = 'reservily_locale';

  Future<void> _load() async {
    final value = await const FlutterSecureStorage().read(key: _kKey);
    if (value != null && supported.contains(value)) {
      _locale = Locale(value);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!supported.contains(locale.languageCode)) return;
    if (locale.languageCode == _locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    await const FlutterSecureStorage().write(
      key: _kKey,
      value: locale.languageCode,
    );
  }
}
