import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('administration'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.campaign_outlined, color: scheme.primary),
              title: Text(context.tr('broadcasts')),
              subtitle: Text(context.tr('broadcastSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/broadcasts'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.people_outline, color: scheme.primary),
              title: Text(context.tr('users')),
              subtitle: Text(context.tr('manageUsers')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/users'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.feedback_outlined, color: scheme.primary),
              title: Text(context.tr('feedbackAdmin')),
              subtitle: Text(context.tr('feedbackAdminSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/feedback'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.storefront_outlined, color: scheme.primary),
              title: Text(context.tr('stores')),
              subtitle: Text(context.tr('manageStores')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/shops'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.person_add_alt_1_outlined, color: scheme.primary),
              title: Text(context.tr('createOwner')),
              subtitle: Text(context.tr('ownerSubtitle')),
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
                'Use broadcasts for announcements, manage user accounts, and '
                'remove stores that are no longer needed.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
