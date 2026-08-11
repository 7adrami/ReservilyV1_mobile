import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class AdminBroadcastsScreen extends StatefulWidget {
  const AdminBroadcastsScreen({super.key});

  @override
  State<AdminBroadcastsScreen> createState() => _AdminBroadcastsScreenState();
}

class _AdminBroadcastsScreenState extends State<AdminBroadcastsScreen> {
  List<Map<String, dynamic>> _broadcasts = [];
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
      _broadcasts = await context.read<ShopService>().adminBroadcasts();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final message = TextEditingController();
    var audience = 'all';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New broadcast',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: audience,
                decoration: const InputDecoration(
                    labelText: 'Audience', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Everyone')),
                  DropdownMenuItem(value: 'barbers', child: Text('Barbers')),
                  DropdownMenuItem(value: 'owners', child: Text('Shop owners')),
                  DropdownMenuItem(value: 'customers', child: Text('Customers')),
                ],
                onChanged: (v) => audience = v ?? 'all',
              ),
              const SizedBox(height: 12),
              AppField('Message', controller: message, maxLines: 4),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Insert name:',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  ActionChip(
                    avatar: const Icon(Icons.person_rounded, size: 16),
                    label: const Text('Full name'),
                    onPressed: () =>
                        _insertPlaceholder(message, '{name}'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 16),
                    label: const Text('First name'),
                    onPressed: () =>
                        _insertPlaceholder(message, '{first name}'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '{name} and {first name} are replaced with each recipient\u2019s name when the broadcast is delivered.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send broadcast'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final text = message.text.trim();
    if (text.isEmpty) {
      if (mounted) showMessage(context, 'Write a message first.');
      return;
    }
    try {
      await context.read<ShopService>().createBroadcast(
          text, audience: audience);
      _load();
      if (mounted) showMessage(context, 'Broadcast sent.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Inserts a placeholder token at the cursor (or appends it) and refocuses.
  void _insertPlaceholder(TextEditingController controller, String token) {
    final selection = controller.selection;
    final isCollapsed = !selection.isValid || selection.isCollapsed;
    final start = isCollapsed ? controller.text.length : selection.start;
    final end = isCollapsed ? controller.text.length : selection.end;
    controller.text = controller.text.replaceRange(start, end, token);
    controller.selection =
        TextSelection.collapsed(offset: start + token.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcasts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('New broadcast'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            if (_loading && _broadcasts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _broadcasts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No broadcasts yet.')),
              ),
            ..._broadcasts.map((b) {
              final sender = b['sender'] as Map<String, dynamic>?;
              final audience = b['audience'] as String? ?? 'all';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.campaign_rounded,
                              color: scheme.primary, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            audience,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Text(
                            b['created_at']?.toString().substring(0, 16) ?? '',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(b['message'] as String,
                          style: const TextStyle(fontSize: 14.5)),
                      if (sender != null) ...[
                        const SizedBox(height: 6),
                        Text('from ${sender['name'] ?? sender['username'] ?? ''}',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
