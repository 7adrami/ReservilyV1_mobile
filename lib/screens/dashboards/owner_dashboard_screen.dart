import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  Map<String, dynamic>? _shop;
  int _team = 0;
  int _pending = 0;
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
      final shop = context.read<ShopService>();
      final s = await shop.ownerShop();
      final team = await shop.ownerTeam();
      final reqs = await shop.ownerRequests();
      setState(() {
        _shop = s['shop'] as Map<String, dynamic>?;
        _team = (team['barbers'] as List<dynamic>? ?? []).length;
        _pending = (reqs['pending'] as List<dynamic>? ?? []).length;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _shop;
    return Scaffold(
      appBar: AppBar(title: const Text('Owner dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (s != null) ...[
              AppPhoto(s['photo'] as String?,
                  height: 150, borderRadius: 16),
              const SizedBox(height: 14),
              Text(s['name'] as String,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${s['city']} · ${s['address']}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('${s['average_rating'] ?? '0.0'} ★ '
                  '(${s['rating_count'] ?? 0})',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: _QuickCard(
                    icon: Icons.group_outlined,
                    label: 'Team',
                    value: '$_team',
                    onTap: () => context.push('/owner/team'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickCard(
                    icon: Icons.how_to_reg_outlined,
                    label: 'Requests',
                    value: '$_pending',
                    onTap: () => context.push('/owner/requests'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickCard(
                    icon: Icons.store_outlined,
                    label: 'Shop',
                    value: '…',
                    onTap: () => context.push('/owner/shop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.store_rounded),
                title: const Text('Manage shop details'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/owner/shop'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('My team'),
                subtitle: const Text('Invite or deactivate barbers'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/owner/team'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.how_to_reg_outlined),
                title: const Text('Join / leave requests'),
                subtitle: _pending > 0 ? Text('$_pending waiting for you') : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/owner/requests'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard(
      {required this.icon, required this.label, required this.value, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, color: scheme.primary, size: 20),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
