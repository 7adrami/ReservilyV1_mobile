import 'package:flutter/foundation.dart';

import '../models/user.dart';

/// Global auth state. Wraps the API client's stored tokens and the current
/// [User] profile so widgets can react to login/logout.
class Session extends ChangeNotifier {
  User? _user;
  bool _restoring = true;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get restoring => _restoring;

  void setRestoring(bool value) {
    _restoring = value;
    notifyListeners();
  }

  void setUser(User? user) {
    _user = user;
    _restoring = false;
    notifyListeners();
  }

  void logout() {
    _user = null;
    _restoring = false;
    notifyListeners();
  }
}
