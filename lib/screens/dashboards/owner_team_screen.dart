import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class OwnerTeamScreen extends StatefulWidget {
  const OwnerTeamScreen({super.key});

  @override
  State<OwnerTeamScreen> createState() => _OwnerTeamScreenState();
}

class _OwnerTeamScreenState extends State<OwnerTeamScreen> {
  List<Map<String, dynamic>> _barbers = [];
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
      final data = await context.read<ShopService>().ownerTeam();
      _barbers = (data['barbers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
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
              const Text('Invite barber',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('They will receive an email with a link to set their password.',
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
                child: const Text('Send invitation'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await context.read<ShopService>().addBarberToTeam(
          username: username.text.trim(), email: email.text.trim());
      _load();
      if (mounted) showMessage(context, 'Invitation sent.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle(Map<String, dynamic> barber) async {
    try {
      await context.read<ShopService>().toggleBarber(barber['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My team')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Invite barber'),
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
            if (_loading && _barbers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _barbers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: Text('No barbers yet. Invite your first one.')),
              ),
            ..._barbers.map((b) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: AppAvatar(b['avatar'] as String?,
                        name: (b['name'] as String? ?? ''), size: 40),
                    title: Text(b['name'] as String),
                    subtitle: Text('@${b['username']}'),
                    trailing: Switch(
                      value: b['is_active'] == true,
                      onChanged: (_) => _toggle(b),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
