import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _users = await context.read<ShopService>().adminUsers(query: _query);
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> user) async {
    final id = user['id'] as int;
    final active = user['is_active'] as bool? ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? context.tr('deactivate') : context.tr('activate')),
        content: Text(context.tr('deactivateConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('stay'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(active ? context.tr('deactivate') : context.tr('activate'))),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await context.read<ShopService>().adminToggleUser(id);
        if (mounted) showMessage(context, context.tr('userUpdated'));
        _load();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('users'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                labelText: context.tr('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                _query = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_error != null) ...[
                    MessageView(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  if (_loading && _users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!_loading && _users.isEmpty && _error == null)
                    MessageView(
                      icon: Icons.people_outline,
                      title: context.tr('noUsers'),
                    ),
                  ..._users.map((u) {
                    final name = (u['name'] as String? ?? '?');
                    final active = u['is_active'] as bool? ?? true;
                    final role = (u['role'] as String? ?? '');
                    final avatar = u['avatar'] as String?;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: AppAvatar(avatar, name: name, size: 44),
                        title: Text(name),
                        subtitle: Text(
                          '@${u['username']} · ${context.tr('role_$role')}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: active
                                    ? scheme.primaryContainer
                                    : scheme.errorContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                active
                                    ? context.tr('active')
                                    : context.tr('inactive'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? scheme.onPrimaryContainer
                                      : scheme.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _toggle(u),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    active ? scheme.error : scheme.primary,
                              ),
                              child: Text(active
                                  ? context.tr('deactivate')
                                  : context.tr('activate')),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
