import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/chat.dart';
import '../../services/chat_identity.dart';
import '../../services/chat_service.dart';
import '../../widgets/common.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ConversationSummary> _conversations = [];
  List<BroadcastInfo> _broadcasts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chat = context.read<ChatService>();
      final conversations = await chat.conversations();
      final broadcasts = await chat.broadcasts();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _broadcasts = broadcasts;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(ConversationSummary c) async {
    final identity = context.read<ChatIdentity>();
    final session = context.read<Session>();
    if (!identity.hasIdentity) {
      final ok = await _ensureIdentity(identity, session);
      if (!ok) return;
    }
    if (mounted) context.push('/chat/${c.id}');
  }

  Future<void> _newChat() async {
    final identity = context.read<ChatIdentity>();
    final session = context.read<Session>();
    if (!identity.hasIdentity) {
      final ok = await _ensureIdentity(identity, session);
      if (!ok) return;
    }
    if (mounted) context.push('/chat/new');
  }

  Future<bool> _ensureIdentity(ChatIdentity identity, Session session) async {
    try {
      identity.setSessionPassword(session.sessionPassword);
      await identity.ensureIdentity(
        username: session.user?.username ?? '',
        passwordPrompt: session.sessionPassword != null
            ? (({required String message}) async {
                return VaultPrompt(result: VaultPromptResult.unlocked, password: session.sessionPassword!);
              })
            : null,
      );
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Announcements',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary)),
              ),
              ..._broadcasts.map((b) => _BroadcastTile(b)),
              const SizedBox(height: 8),
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
          if (c.other.hasKey)
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
  const _BroadcastTile(this.b);

  final BroadcastInfo b;

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
        onTap: () => context.push('/chat/broadcasts'),
      ),
    );
  }
}
