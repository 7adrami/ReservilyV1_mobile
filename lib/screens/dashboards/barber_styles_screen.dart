import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberStylesScreen extends StatefulWidget {
  const BarberStylesScreen({super.key});

  @override
  State<BarberStylesScreen> createState() => _BarberStylesScreenState();
}

class _BarberStylesScreenState extends State<BarberStylesScreen> {
  List<Map<String, dynamic>> _styles = [];
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
      _styles = await context.read<ShopService>().barberStyles();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit([Map<String, dynamic>? style]) async {
    final isEdit = style != null;
    final name = TextEditingController(text: style?['name'] as String? ?? '');
    final price = TextEditingController(text: style?['price']?.toString() ?? '');
    final duration = TextEditingController(
        text: style?['duration_minutes']?.toString() ?? '30');
    final description =
        TextEditingController(text: style?['description'] as String? ?? '');

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
              Text(isEdit ? 'Edit service' : 'New service',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              AppField('Name', controller: name),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppField('Price (${'UM'})', controller: price,
                        keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppField('Minutes', controller: duration,
                        keyboardType: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppField('Description (optional)', controller: description),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isEdit ? 'Save changes' : 'Add service'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final shop = context.read<ShopService>();
    try {
      if (isEdit) {
        await shop.updateBarberStyle(style['id'] as int,
            name: name.text.trim(),
            price: price.text.trim(),
            durationMinutes: int.tryParse(duration.text.trim()));
      } else {
        await shop.addBarberStyle(
          name: name.text.trim(),
          price: price.text.trim(),
          durationMinutes: int.tryParse(duration.text.trim()),
          description: description.text.trim(),
        );
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setActive(Map<String, dynamic> style, bool active) async {
    try {
      await context
          .read<ShopService>()
          .updateBarberStyle(style['id'] as int, isActive: active);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> style) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('“${style['name']}” will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ShopService>().deleteBarberStyle(style['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New service'),
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
            if (_loading && _styles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _styles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No services yet. Add your first one.')),
              ),
            ..._styles.map((s) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Icon(Icons.content_cut_rounded,
                              color: scheme.onPrimaryContainer, size: 20),
                        ),
                        title: Text(s['name'] as String),
                        subtitle: Text(
                            '${money(num.tryParse('${s['price']}'))} · ${s['duration_minutes']} min'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _addOrEdit(s),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: scheme.error),
                              onPressed: () => _delete(s),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        title: const Text('Available for booking',
                            style: TextStyle(fontSize: 13.5)),
                        value: s['is_active'] != false,
                        onChanged: (v) => _setActive(s, v),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
