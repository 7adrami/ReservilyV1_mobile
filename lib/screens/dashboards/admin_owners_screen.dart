import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class AdminOwnersScreen extends StatefulWidget {
  const AdminOwnersScreen({super.key});

  @override
  State<AdminOwnersScreen> createState() => _AdminOwnersScreenState();
}

class _AdminOwnersScreenState extends State<AdminOwnersScreen> {
  bool _busy = false;

  Future<void> _create() async {
    final username = TextEditingController();
    final email = TextEditingController();
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
              const Text('Create shop owner',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('They will receive an email with a setup link and code.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              AppField('Username', controller: username),
              const SizedBox(height: 12),
              AppField('Email', controller: email,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ShopService>().adminCreateOwner(
          username.text.trim(), email.text.trim());
      if (mounted) {
        showMessage(context, 'Owner account created and setup email sent.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create shop owner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.primaryContainer.withOpacity(0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                        'New owners get a one-time setup link by email. After '
                        'setting a password, they can register their barbershop.'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(_busy ? 'Creating…' : 'Create a shop owner'),
          ),
        ],
      ),
    );
  }
}
