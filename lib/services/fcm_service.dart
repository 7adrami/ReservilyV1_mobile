import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../core/api_client.dart';
import 'notification_service.dart';

/// Firebase Cloud Messaging bridge (Android only).
///
/// While the app is running, incoming messages are detected by the chat
/// polling and shown with `flutter_local_notifications` (see
/// `NotificationService`). FCM covers the rest: when the Android app is in
/// the background or killed, the server pushes a system notification through
/// Firebase. Messages are end-to-end encrypted, so the notification carries
/// no message preview. Tapping it opens the conversation.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  ApiClient? _api;
  FirebaseMessaging? _messaging;
  bool _initialized = false;
  String? _token;

  /// Set by the app root to open a chat room when the user taps an FCM
  /// notification.
  void Function(int conversationId)? onOpenNotificationTap;

  /// Set by the app root to open the broadcasts inbox when the user taps a
  /// broadcast FCM notification.
  void Function()? onOpenBroadcastTap;

  bool get _android => !kIsWeb && Platform.isAndroid;

  Future<void> attach(ApiClient api) async {
    _api = api;
    if (!_android) return;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return; // Firebase project not configured — app still works via polling.
    }
    _messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
    _messaging!.getToken().then(_storeToken);
    _messaging!.onTokenRefresh.listen(_storeToken);
    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _handleTap(message));
    final initial = await _messaging!.getInitialMessage();
    if (initial != null) {
      // App was launched from the notification; open the chat once the UI is
      // up (the callback set by the root ignores it before first frame).
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
    }
    _initialized = true;
  }

  /// Registers (or re-registers) the current device token with the server.
  /// Existing tokens for the same user + device are replaced.
  Future<void> registerToken() async {
    if (!_initialized) return;
    final token = _token;
    final api = _api;
    if (token == null || token.isEmpty || api == null) return;
    try {
      await api.request(
        '/api/notifications/token/',
        method: 'POST',
        body: {'token': token, 'platform': 'android'},
      );
    } catch (_) {
      // Server unreachable or token invalid — retried on next login.
    }
  }

  /// Removes the registered token when the user logs out.
  Future<void> deregisterToken() async {
    if (!_initialized) return;
    final token = _token;
    final api = _api;
    if (token == null || token.isEmpty || api == null) return;
    try {
      await api.request(
        '/api/notifications/token/',
        method: 'POST',
        body: {'token': token, 'remove': true},
      );
    } catch (_) {}
  }

  Future<void> _storeToken(String? token) async {
    _token = token;
    if (token != null) await registerToken();
  }

  void _handleTap(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'broadcast') {
      onOpenBroadcastTap?.call();
      return;
    }
    final id = int.tryParse('${message.data['conversation_id'] ?? ''}');
    if (id != null) onOpenNotificationTap?.call(id);
  }

  /// Foreground messages: chat is handled by polling (to avoid duplicates),
  /// so we only surface local notifications for broadcasts and reactions.
  void _handleForeground(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'broadcast') {
      NotificationService.instance.showBroadcast(
        message.notification?.title ?? 'Reservily',
        message.notification?.body ?? 'You have a new announcement',
      );
    } else if (type == 'reaction') {
      final id = int.tryParse('${message.data['conversation_id'] ?? ''}');
      final name = message.notification?.title ?? 'Someone';
      if (id != null) NotificationService.instance.showReaction(id, name);
    }
  }

  // Called by the OS when a notification arrives while the app is terminated
  // (Android). Only notification-payload messages are sent, so the system
  // displays them without needing this handler.
  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {}
}