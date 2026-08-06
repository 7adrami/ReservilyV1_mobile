import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberWalletsScreen extends StatefulWidget {
  const BarberWalletsScreen({super.key});

  @override
  State<BarberWalletsScreen> createState() => _BarberWalletsScreenState();
}

class _BarberWalletsScreenState extends State<BarberWalletsScreen> {
  List<Map<String, dynamic>> _wallets = [];
  bool _loading = true;
  String? _error;

  static const _apps = [
    'Orange Money',
    'Moov Money',
    'Wave',
    'MTN MoMo',
    'Airtel Money',
    'Bank transfer',
    'Cash',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().myWallets();
      _wallets = (data['wallets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .toList();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([int? index]) async {
    final isEdit = index != null;
    final app = TextEditingController(
        text: isEdit ? _wallets[index]['app'] as String : '');
    final phone = TextEditingController(
        text: isEdit ? _wallets[index]['phone'] as String : '');

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
              Text(isEdit ? 'Edit wallet' : 'Add wallet',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: app.text.isEmpty ? null : app.text,
                decoration: const InputDecoration(
                    labelText: 'Payment method', border: OutlineInputBorder()),
                items: _apps
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => app.text = v ?? '',
              ),
              const SizedBox(height: 12),
              AppField('Phone number', controller: phone,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isEdit ? 'Save' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final list = List<Map<String, dynamic>>.from(_wallets);
    if (isEdit) {
      list[index] = {'app': app.text, 'phone': phone.text.trim()};
    } else {
      list.add({'app': app.text, 'phone': phone.text.trim()});
    }
    try {
      await context.read<ShopService>().saveWallets(list);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _remove(int index) async {
    final list = List<Map<String, dynamic>>.from(_wallets)..removeAt(index);
    try {
      await context.read<ShopService>().saveWallets(list);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add wallet'),
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
            if (_loading && _wallets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _wallets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No wallets yet. Add the ones clients can pay to.')),
              ),
            ..._wallets.indexed.map((entry) {
              final (i, w) = entry;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.account_balance_wallet_rounded,
                        color: scheme.onPrimaryContainer, size: 20),
                  ),
                  title: Text(w['app'] as String),
                  subtitle: Text(w['phone'] as String),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _edit(i),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                        onPressed: () => _remove(i),
                      ),
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
