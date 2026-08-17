import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows local system notifications (Android heads-up/status bar and
/// Windows toast) when a new chat message arrives for the signed-in user.
///
/// The Flutter app polls the chat API while the user is logged in, so new
/// messages are detected near real-time. Messages are end-to-end encrypted,
/// so notifications never contain a text preview.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Set by the app root to open a chat room when a notification is tapped.
  void Function(int conversationId)? onOpenConversation;

  /// Set by the app root to open the broadcasts inbox when a broadcast
  /// notification is tapped.
  void Function()? onOpenBroadcast;

  static const String _channelId = 'chat_messages';

  Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      windows: WindowsInitializationSettings(
        appName: 'Reservily',
        appUserModelId: 'Reservily.App',
        guid: '82493A7A-2C38-4F9E-9D1B-A1B2C3D4E5F6',
      ),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        if (payload.startsWith('chat:')) {
          final id = int.tryParse(payload.substring(5));
          if (id != null) onOpenConversation?.call(id);
        } else if (payload.startsWith('broadcast:')) {
          onOpenBroadcast?.call();
        }
      },
    );
    _ready = true;
  }

  /// Asks for notification permission (Android 13+ shows a system dialog).
  Future<void> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showNewMessage(int conversationId, String senderName) async {
    if (!_ready) return;
    await _plugin.show(
      conversationId,
      'New message from $senderName',
      'Reservily',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat messages',
          channelDescription: 'New chat messages from your contacts',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: 'chat:$conversationId',
    );
  }

  /// Shows a local notification for a new admin broadcast (foreground only;
  /// when the app is killed FCM displays the system notification instead).
  Future<void> showBroadcast(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      'broadcast'.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat messages',
          channelDescription: 'New chat messages from your contacts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: 'broadcast:',
    );
  }

  /// Shows a local notification when someone reacts to the user's message
  /// (foreground only; FCM displays it when the app is killed).
  Future<void> showReaction(int conversationId, String reactorName) async {
    if (!_ready) return;
    await _plugin.show(
      conversationId,
      '$reactorName reacted to your message',
      'Reservily',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat messages',
          channelDescription: 'New chat messages from your contacts',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: 'chat:$conversationId',
    );
  }
}