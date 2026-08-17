import 'package:flutter/foundation.dart';

/// Global, app-wide unread counters for the chat tab.
///
/// `ChatListScreen` polls the API every few seconds and publishes the total
/// number of unread direct messages here. `HomeShell` reads it to show a
/// WhatsApp-style count badge on the message (chat) navigation icon, so new
/// DMs are visible even when the chat tab isn't open.
class ChatBadgeNotifier extends ChangeNotifier {
  ChatBadgeNotifier._();
  static final ChatBadgeNotifier instance = ChatBadgeNotifier._();

  int _unread = 0;

  int get unread => _unread;

  void update(int unread) {
    final next = unread < 0 ? 0 : unread;
    if (_unread == next) return;
    _unread = next;
    notifyListeners();
  }

  void clear() => update(0);
}
