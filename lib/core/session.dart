import 'package:flutter/foundation.dart';

import '../models/user.dart';

/// Global auth state. Wraps the API client's stored tokens and the current
/// [User] profile so widgets can react to login/logout.
class Session extends ChangeNotifier {
  User? _user;
  bool _restoring = true;
  String? _sessionPassword;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get restoring => _restoring;
  String? get sessionPassword => _sessionPassword;

  void setRestoring(bool value) {
    _restoring = value;
    notifyListeners();
  }

  void setUser(User? user, {String? password}) {
    _user = user;
    _sessionPassword = password;
    _restoring = false;
    notifyListeners();
  }

  void logout() {
    _user = null;
    _sessionPassword = null;
    _restoring = false;
    notifyListeners();
  }
}
