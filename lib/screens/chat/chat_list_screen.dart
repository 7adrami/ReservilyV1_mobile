import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/chat_badge.dart';
import '../../models/chat.dart';
import '../../services/chat_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/common.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ConversationSummary> _conversations = [];
  List<BroadcastInfo> _broadcasts = [];
  Set<int> _dismissedIds = {};
  final Map<int, int> _knownUnread = {};
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // New messages appear on the list within ~3s of being sent (near
    // real-time without server push on the free hosting plan).
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chat = context.read<ChatService>();
      final results = await Future.wait([
        chat.conversations(),
        chat.broadcasts(),
      ]);
      const storage = FlutterSecureStorage();
      final dismissedRaw = await storage.read(key: 'reservily_dismissed_broadcasts') ?? '[]';
      final List<dynamic> dismissedList = jsonDecode(dismissedRaw);
      final dismissedSet = dismissedList.cast<int>().toSet();

      if (mounted) {
        setState(() {
          _conversations = results[0] as List<ConversationSummary>;
          _broadcasts = results[1] as List<BroadcastInfo>;
          _dismissedIds = dismissedSet;
          _error = null;
        });
      }
      // Baseline only: no notifications for what was already in the inbox.
      _recordUnread(_conversations);
      _publishBadge(_conversations);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Background refresh: updates the lists in place without a spinner.
  Future<void> _silentRefresh() async {
    if (_refreshing || _loading || !mounted) return;
    _refreshing = true;
    try {
      final chat = context.read<ChatService>();
      final results = await Future.wait([
        chat.conversations(),
        chat.broadcasts(),
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = results[0] as List<ConversationSummary>;
        _broadcasts = results[1] as List<BroadcastInfo>;
        _error = null;
      });
      _notifyNewMessages(_conversations);
      _publishBadge(_conversations);
    } catch (_) {
      // Transient; the next tick retries.
    } finally {
      _refreshing = false;
    }
  }

  /// Publishes the total unread DM count to the app-wide badge notifier so the
  /// message (chat) navigation icon shows a WhatsApp-style count.
  void _publishBadge(List<ConversationSummary> conversations) {
    final total = conversations.fold<int>(0, (sum, c) => sum + c.unread);
    try {
      context.read<ChatBadgeNotifier>().update(total);
    } catch (_) {}
  }

  /// Remembers the current unread counts so the next poll can spot increases.
  void _recordUnread(List<ConversationSummary> conversations) {
    final ids = conversations.map((c) => c.id).toSet();
    _knownUnread.removeWhere((id, _) => !ids.contains(id));
    for (final c in conversations) {
      _knownUnread[c.id] = c.unread;
    }
  }

  /// Fires a system notification for each conversation whose unread count
  /// grew since the last poll (i.e. a new message arrived). Only fires while
  /// the app is in the foreground — in the background/killed state FCM
  /// handles the notification.
  void _notifyNewMessages(List<ConversationSummary> conversations) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _recordUnread(conversations);
      return;
    }
    for (final c in conversations) {
      final previous = _knownUnread[c.id];
      if (previous != null && c.unread > previous && !c.lastIsMe && !_loading) {
        NotificationService.instance.showNewMessage(c.id, c.other.name);
      }
    }
    _recordUnread(conversations);
  }

  void _openConversation(ConversationSummary c) {
    context.push('/chat/${c.id}', extra: c.other);
  }

  void _newChat() {
    context.push('/chat/new');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Compute visible broadcasts once to avoid declaration inside collection literals.
    final List<BroadcastInfo> visibleBroadcasts = _broadcasts.where((b) => !_dismissedIds.contains(b.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'Broadcasts',
            icon: Badge(
              isLabelVisible: _broadcasts.any((b) => b.isNew),
              child: const Icon(Icons.campaign_outlined),
            ),
            onPressed: () => context.push('/chat/broadcasts'),
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
            ],
            if (_loading && _conversations.isEmpty && _broadcasts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_broadcasts.isNotEmpty) ...[
              if (visibleBroadcasts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Announcements',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary)),
                ),
                ...visibleBroadcasts.map((b) => _BroadcastTile(
                      b: b,
                      onDismiss: () async {
                        setState(() {
                          _dismissedIds.add(b.id);
                        });
                        const storage = FlutterSecureStorage();
                        await storage.write(
                          key: 'reservily_dismissed_broadcasts',
                          value: jsonEncode(_dismissedIds.toList()),
                        );
                      },
                    )),
                const SizedBox(height: 8),
              ],
            ],
            if (_conversations.isEmpty && !_loading && _error == null)
              const MessageView(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No conversations yet',
                subtitle: 'Tap the icon above to start a chat with anyone.',
              )
            else
              ..._conversations.map((c) => _ConversationTile(
                    c: c,
                    onTap: () => _openConversation(c),
                  )),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.c, required this.onTap});

  final ConversationSummary c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = c.lastMessageAt;
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          AppAvatar(c.other.avatar, name: c.other.name, size: 46),
          if (!c.other.hasKey)
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(Icons.lock_rounded,
                  size: 14, color: scheme.primary),
            ),
        ],
      ),
      title: Text(c.other.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(last == null
          ? 'Say hello 👋'
          : '${c.lastIsMe ? 'You · ' : ''}Encrypted'),      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null)
            Text(
              _time(last),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          if (c.unread > 0)
            Badge(
              label: Text('${c.unread}'),
              backgroundColor: scheme.primary,
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  static String _time(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) {
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}/${t.month}';
  }
}

class _BroadcastTile extends StatelessWidget {
  const _BroadcastTile({required this.b, required this.onDismiss});

  final BroadcastInfo b;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: b.isNew ? scheme.primaryContainer.withOpacity(0.4) : null,
      child: ListTile(
        leading: Icon(Icons.campaign_rounded, color: scheme.primary),
        title: Text(b.message,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(b.createdAt.toLocal().toString().substring(0, 16)),
        trailing: IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: 'Dismiss',
          onPressed: onDismiss,
        ),
        onTap: () => context.push('/chat/broadcasts'),
      ),
    );
  }
}
