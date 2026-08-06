import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberRequestsScreen extends StatefulWidget {
  const BarberRequestsScreen({super.key});

  @override
  State<BarberRequestsScreen> createState() => _BarberRequestsScreenState();
}

class _BarberRequestsScreenState extends State<BarberRequestsScreen> {
  List<Map<String, dynamic>> _shops = [];
  List<Map<String, dynamic>> _pending = [];
  Set<int> _myShopIds = {};
  bool _loading = true;
  String? _error;
  int? _busyShopId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().barberRequests();
      _shops = (data['shops'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      _pending = (data['pending'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      _myShopIds = (data['my_shops'] as List<dynamic>? ?? [])
          .map((e) => (e as Map<String, dynamic>)['id'] as int)
          .toSet();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request(int shopId, String kind) async {
    setState(() => _busyShopId = shopId);
    try {
      await context.read<ShopService>().sendBarberRequest(shopId, kind);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyShopId = null);
    }
  }

  Future<void> _cancel(int pk) async {
    try {
      await context.read<ShopService>().cancelBarberRequest(pk);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Shops & requests')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            if (_pending.isNotEmpty) ...[
              const Text('Pending requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ..._pending.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                          r['kind'] == 'join'
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          color: scheme.tertiary),
                      title: Text((r['shop'] as Map<String, dynamic>)['name'] as String),
                      subtitle: Text(r['kind'] == 'join' ? 'Requested to join' : 'Requested to leave'),
                      trailing: IconButton(
                        icon: Icon(Icons.close_rounded, color: scheme.error),
                        onPressed: () => _cancel(r['id'] as int),
                        tooltip: 'Cancel request',
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
            ],
            const Text('All barbershops',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_loading && _shops.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            ..._shops.map((s) {
              final id = s['id'] as int;
              final isMine = _myShopIds.contains(id);
              final busy = _busyShopId == id;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(isMine ? Icons.work_rounded : Icons.store_outlined,
                      color: isMine ? scheme.primary : scheme.outline),
                  title: Text(s['name'] as String),
                  subtitle: Text('${s['city'] ?? ''}${isMine ? ' · you work here' : ''}'),
                  trailing: isMine
                      ? TextButton(
                          onPressed: busy ? null : () => _request(id, 'leave'),
                          child: const Text('Request leave'))
                      : FilledButton.tonal(
                          onPressed: busy ? null : () => _request(id, 'join'),
                          child: const Text('Request join')),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
