import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class OwnerRequestsScreen extends StatefulWidget {
  const OwnerRequestsScreen({super.key});

  @override
  State<OwnerRequestsScreen> createState() => _OwnerRequestsScreenState();
}

class _OwnerRequestsScreenState extends State<OwnerRequestsScreen> {
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _resolved = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().ownerRequests();
      _pending = (data['pending'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      _resolved = (data['resolved'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> r, String action) async {
    setState(() => _busyId = r['id'] as int);
    try {
      await context.read<ShopService>().resolveRequest(r['id'] as int, action);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Join / leave requests')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            const Text('Pending',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_pending.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No pending requests.'),
              ),
            ..._pending.map((r) {
              final busy = _busyId == r['id'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(initialsOf(r['barber_name'] as String? ?? '?')),
                  ),
                  title: Text(r['barber_name'] as String),
                  subtitle: Text(
                      '${r['kind'] == 'join' ? 'Wants to join' : 'Wants to leave'} · '
                      '${r['created_at']?.toString().substring(0, 10) ?? ''}'),
                  isThreeLine: true,
                  trailing: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.check_circle_rounded,
                                  color: scheme.primary),
                              onPressed: () => _resolve(r, 'approve'),
                              tooltip: 'Approve',
                            ),
                            IconButton(
                              icon: Icon(Icons.cancel_rounded,
                                  color: scheme.error),
                              onPressed: () => _resolve(r, 'reject'),
                              tooltip: 'Reject',
                            ),
                          ],
                        ),
                ),
              );
            }),
            const SizedBox(height: 20),
            const Text('Recent',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ..._resolved.map((r) => ListTile(
                  dense: true,
                  leading: Icon(
                      r['status'] == 'approved'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: r['status'] == 'approved'
                          ? scheme.primary
                          : scheme.error),
                  title: Text(r['barber_name'] as String),
                  subtitle: Text(
                      '${r['status']} · ${r['kind'] == 'join' ? 'join' : 'leave'}'),
                )),
          ],
        ),
      ),
    );
  }
}
