import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.campaign_outlined, color: scheme.primary),
              title: const Text('Broadcasts'),
              subtitle: const Text('Send announcements to everyone'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/broadcasts'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.storefront_outlined, color: scheme.primary),
              title: const Text('Create shop owner'),
              subtitle: const Text('Set up a new barbershop owner'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/owners'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: scheme.primaryContainer.withOpacity(0.4),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Use broadcasts for announcements and create owner accounts '
                'for new barbershops that need onboarding.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
