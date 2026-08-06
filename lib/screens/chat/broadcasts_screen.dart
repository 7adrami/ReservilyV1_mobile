import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../services/chat_service.dart';
import '../../widgets/common.dart';

class BroadcastsScreen extends StatefulWidget {
  const BroadcastsScreen({super.key});

  @override
  State<BroadcastsScreen> createState() => _BroadcastsScreenState();
}

class _BroadcastsScreenState extends State<BroadcastsScreen> {
  List<BroadcastInfo> _broadcasts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final chat = context.read<ChatService>();
      _broadcasts = await chat.broadcastHistory();
      for (final b in _broadcasts.where((b) => b.isNew)) {
        try {
          await chat.broadcastRead(b.id);
        } catch (_) {}
      }
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
            ],
            if (_loading && _broadcasts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _broadcasts.isEmpty && _error == null)
              const MessageView(
                icon: Icons.campaign_outlined,
                title: 'No announcements yet',
              ),
            ..._broadcasts.map((b) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.campaign_rounded,
                                color: scheme.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _audienceLabel(b.audience),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                            Text(
                              b.createdAt.toLocal().toString().substring(0, 16),
                              style: TextStyle(
                                  fontSize: 11.5, color: scheme.outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(b.message,
                            style: const TextStyle(
                                fontSize: 15, height: 1.35)),
                        if (b.sender != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              AppAvatar(b.sender!.avatar,
                                  name: b.sender!.name, size: 22),
                              const SizedBox(width: 8),
                              Text('from ${b.sender!.name}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  static String _audienceLabel(String audience) {
    switch (audience) {
      case 'barbers':
        return 'For barbers';
      case 'owners':
        return 'For shop owners';
      case 'customers':
        return 'For customers';
      default:
        return 'For everyone';
    }
  }
}
