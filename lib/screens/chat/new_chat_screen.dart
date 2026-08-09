import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/chat.dart';
import '../../services/chat_service.dart';
import '../../services/chat_identity.dart';
import '../../widgets/common.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  List<ChatUserInfo> _users = [];
  bool _searching = false;
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = value.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _users = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final users = await context.read<ChatService>().users(q);
        if (mounted && _query == q) {
          setState(() => _users = users);
        }
      } catch (e) {
        if (mounted) showError(context, e);
      } finally {
        if (mounted && _query == q) setState(() => _searching = false);
      }
    });
  }

  Future<void> _start(ChatUserInfo u) async {
    try {
      final session = context.read<Session>();
      final chat = context.read<ChatService>();
      final identity = context.read<ChatIdentity>();
      final result = await chat.start(u.username);
      if (!identity.hasIdentity) {
        final pw = session.sessionPassword;
        identity.setSessionPassword(pw);
        await identity.ensureIdentity(
          username: session.user?.username ?? u.username,
          passwordPrompt: pw != null
              ? (({required String message}) async {
                  return VaultPrompt(result: VaultPromptResult.unlocked, password: pw);
                })
              : ({required String message}) async {
                  return VaultPrompt(result: VaultPromptResult.cancelled);
                },
        );
      }
      if (mounted) context.go('/chat/${result.id}', extra: result.other);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              autofocus: true,
              onChanged: (v) {
                _query = v;
                _onChanged(v);
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by username or name…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _users.isEmpty
                ? Center(
                    child: Text('Type to find people',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, i) {
                      final u = _users[i];
                      return ListTile(
                        leading: AppAvatar(u.avatar, name: u.name, size: 44),
                        title: Text(u.name),
                        subtitle: Text('@${u.username}'),
                        trailing: Icon(Icons.chat_bubble_outline_rounded,
                            color: scheme.primary),
                        onTap: () => _start(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
