import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/chat.dart';
import '../../services/chat_identity.dart';
import '../../services/chat_room.dart';
import '../../services/chat_service.dart';
import '../../widgets/common.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.conversationId, this.other});

  final int conversationId;
  final ChatUserInfo? other;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  ChatRoomController? _room;
  bool _ready = false;
  String? _initError;

  final TextEditingController _composer = TextEditingController();
  bool _sending = false;
  final Map<int, String> _decodedEmoji = {};

  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = context.read<Session>();
    final user = session.user;
    if (user == null) return;
    final identity = context.read<ChatIdentity>();
    final chat = context.read<ChatService>();
    try {
      if (!identity.hasIdentity) {
        await identity.ensureIdentity(
          username: user.username,
          passwordPrompt: _vaultPrompt,
        );
      }
      ChatUserInfo other = widget.other ?? await _findOther();
      final room = ChatRoomController(
        chatService: chat,
        identity: identity,
        myUsername: user.username,
        myUserId: user.id,
        myName: user.name,
      );
      room.addListener(_onRoomChanged);
      _room = room;
      await room.open(widget.conversationId, other);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _initError = friendlyError(e));
    }
  }

  Future<ChatUserInfo> _findOther() async {
    final list = await context.read<ChatService>().conversations();
    final found = list.where((c) => c.id == widget.conversationId).toList();
    if (found.isNotEmpty) return found.first.other;
    throw Exception('Conversation not found.');
  }

  Future<VaultPrompt> _vaultPrompt({required String message}) async {
    if (!mounted) return const VaultPrompt(result: VaultPromptResult.cancelled);
    final password = TextEditingController();
    final result = await showDialog<_DialogAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          var reset = false;
          return AlertDialog(
            title: const Text('Restore encrypted chat keys'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Account password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() => reset = !reset),
                    child: const Text('I forgot my password — start fresh'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                    context,
                    _DialogAnswer(
                        reset: reset,
                        password: password.text,
                        cancelled: reset ? false : password.text.isEmpty)),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || result.cancelled) {
      return const VaultPrompt(result: VaultPromptResult.cancelled);
    }
    if (result.reset) {
      return const VaultPrompt(result: VaultPromptResult.reset);
    }
    return VaultPrompt(
        result: VaultPromptResult.unlocked, password: result.password);
  }

  void _onRoomChanged() {
    if (mounted) {
      setState(() {
        _decodedEmoji.clear();
        for (final m in _room?.messages ?? const <ChatMessage>[]) {
          for (final r in m.reactions) {
            if (r.ciphertext != null) {
              _room!.decryptEmoji(r).then((emoji) {
                if (emoji != null && mounted) {
                  setState(() => _decodedEmoji[r.id] = emoji);
                }
              });
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomChanged);
    _room?.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    final room = _room;
    if (room == null || !room.unlocked) return;
    setState(() => _sending = true);
    try {
      await room.sendText(text);
      _composer.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMedia() async {
    final room = _room;
    if (room == null || !room.unlocked) return;
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      if (mounted) showError(context, 'Image too large (max 8 MB).');
      return;
    }
    try {
      await room.sendMedia(
        bytes: bytes,
        name: file.name,
        mime: _mimeOf(file.name),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  static String _mimeOf(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    final room = _room;
    if (room == null) return;
    final mine = m.reactions.where((r) => r.userId == room.myUserId).toList();
    try {
      if (mine.isEmpty) {
        await room.setReaction(m, emoji);
      } else {
        await room.removeReaction(m);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _messageMenu(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(context);
                _reactionPicker(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _room?.startReply(m);
              },
            ),
            if (m.isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete for everyone'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _room?.deleteForEveryone(m);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Delete for me'),
              onTap: () async {
                Navigator.pop(context);
                try {
                    await _room?.hideForMe(m);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _reactionPicker(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final emoji in _reactions)
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.pop(context);
                  _toggleReaction(m, emoji);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final room = _room;

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: MessageView(message: _initError!, onRetry: _init),
      );
    }
    if (room == null || !_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const LoadingView(),
      );
    }

    final other = room.other;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: other == null
            ? const Text('Chat')
            : Row(
                children: [
                  AppAvatar(other.avatar, name: other.name, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(other.name,
                            style: const TextStyle(fontSize: 15.5)),
                        Text(
                          room.unlocked
                              ? 'End-to-end encrypted'
                              : (room.status == RoomStatus.noKey
                                  ? "They haven't set up encryption yet"
                                  : 'Waiting for key…'),
                          style: TextStyle(
                              fontSize: 11.5,
                              color: room.unlocked
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    room.unlocked
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 16,
                    color:
                        room.unlocked ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: room.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded,
                            size: 48, color: scheme.outline),
                        const SizedBox(height: 10),
                        Text('No messages yet',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    reverse: true,
                    itemCount: room.messages.length,
                    itemBuilder: (context, i) {
                      final m = room.messages[room.messages.length - 1 - i];
                      return _MessageBubble(
                        room: room,
                        message: m,
                        emoji: (id) => _decodedEmoji[id],
                        onLongPress: () => _messageMenu(m),
                        onEmojiTap: (emoji) => _toggleReaction(m, emoji),
                      );
                    },
                  ),
          ),
          if (room.replyTo != null)
            Container(
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _replyPreview(room.replyTo!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  IconButton(
                    onPressed: room.clearReply,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          _Composer(
            controller: _composer,
            sending: _sending,
            unlocked: room.unlocked,
            onSend: _sendText,
            onMedia: _sendMedia,
          ),
        ],
      ),
    );
  }

  String _replyPreview(ChatMessage m) {
    final p = m.decrypted;
    if (p?.type == 'media') return 'Reply to 📷 ${p?.text ?? 'Photo'}';
    return 'Replying to ${p?.text ?? '…'}';
  }
}

class _DialogAnswer {
  const _DialogAnswer(
      {required this.password, required this.reset, required this.cancelled});

  final String password;
  final bool reset;
  final bool cancelled;
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.unlocked,
    required this.onSend,
    required this.onMedia,
  });

  final TextEditingController controller;
  final bool sending;
  final bool unlocked;
  final VoidCallback onSend;
  final VoidCallback onMedia;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: unlocked ? onMedia : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'Send photo',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: unlocked,
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: unlocked ? 'Message…' : 'Encryption not ready…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton.filled(
                    onPressed: unlocked ? onSend : null,
                    icon: const Icon(Icons.send_rounded, size: 20),
                    tooltip: 'Send',
                  ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.room,
    required this.message,
    required this.emoji,
    required this.onLongPress,
    required this.onEmojiTap,
  });

  final ChatRoomController room;
  final ChatMessage message;
  final String? Function(int reactionId) emoji;
  final VoidCallback onLongPress;
  final void Function(String emoji) onEmojiTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = message.isMe;
    final payload = message.decrypted;
    final isMedia = payload?.type == 'media';
    final failed = message.decryptFailed;

    Widget content;
    if (failed) {
      content = Container(
        padding: const EdgeInsets.all(8),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 14),
            SizedBox(width: 6),
            Text('Message cannot be decrypted', style: TextStyle(fontSize: 12.5)),
          ],
        ),
      );
    } else if (isMedia && payload!.media != null) {
      content = FutureBuilder(
        future: room.mediaFor(message),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Media unavailable', style: TextStyle(fontSize: 12.5)),
            );
          }
          if (!snapshot.hasData) {
            return Container(
              width: 200,
              height: 120,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final media = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  media.bytes,
                  width: 220,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 220,
                    height: 120,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              if ((payload.text ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(payload.text!),
              ],
            ],
          );
        },
      );
    } else {
      content = Text(payload?.text ?? '',
          style: const TextStyle(fontSize: 15, height: 1.3));
    }

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: isMedia ? const EdgeInsets.all(6) : const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: me
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(me ? 16 : 4),
          bottomRight: Radius.circular(me ? 4 : 16),
        ),
      ),
      child: content,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment:
            me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.decrypted != null && (message.decrypted!.replyTo != null))
            _ReplyChip(
              text: message.decrypted!.replyText,
              me: me,
            ),
          Row(
            mainAxisAlignment:
                me ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (me) ..._tick(context),
              Flexible(child: GestureDetector(
                onLongPress: onLongPress,
                child: bubble,
              )),
            ],
          ),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment:
                    me ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  _ReactionChip(
                    reaction: message.reactions.first,
                    emojiText: emoji(message.reactions.first.id),
                    isMine: message.reactions.first.userId == room.myUserId,
                    onTap: () => onEmojiTap(''),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _tick(BuildContext context) {
    final m = message;
    final read = m.readAt != null;
    final delivered = m.deliveredAt != null || m.isMe;
    IconData icon;
    if (read) {
      icon = Icons.done_all_rounded;
    } else if (delivered) {
      icon = Icons.done_all_rounded;
    } else {
      icon = Icons.done_rounded;
    }
    return [
      Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Icon(icon,
            size: 13,
            color: read
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline),
      ),
    ];
  }
}

class _ReplyChip extends StatelessWidget {
  const _ReplyChip({required this.text, required this.me});

  final String? text;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: me
            ? scheme.primary.withOpacity(0.12)
            : scheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.reply_rounded, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text ?? 'Reply',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.reaction,
    required this.emojiText,
    required this.isMine,
    required this.onTap,
  });

  final ReactionInfo reaction;
  final String? emojiText;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isMine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: isMine ? Border.all(color: scheme.primary) : null,
        ),
        child: Text(emojiText ?? reaction.name ?? '👍',
            style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
