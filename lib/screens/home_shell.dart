import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/chat_badge.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../widgets/common.dart';
import 'chat/chat_list_screen.dart';
import 'dashboards/admin_dashboard_screen.dart';
import 'dashboards/barber_dashboard_screen.dart';
import 'dashboards/owner_dashboard_screen.dart';
import 'home/shops_screen.dart';
import 'home/profile_screen.dart';
import 'home/reservations_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (session.restoring) {
      return const Scaffold(body: LoadingView());
    }
    final user = session.user;
    if (user == null) {
      return const Scaffold(body: LoadingView());
    }

    // WhatsApp-style unread count shown on the message (chat) navigation icon.
    final badge = context.watch<ChatBadgeNotifier>();

    final List<Widget> tabs;
    final List<NavigationDestination> destinations;
    if (user.isCustomer) {
      tabs = [
        const ShopsScreen(),
        ReservationsScreen(onFindBarber: () => setState(() => _index = 0)),
        const ChatListScreen(),
        const ProfileScreen(),
      ];
      destinations = [
        NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: context.tr('navExplore')),
        NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: context.tr('navBookings')),
        NavigationDestination(
            icon: Badge(
              isLabelVisible: badge.unread > 0,
              label: Text('${badge.unread}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: context.tr('navChat')),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: context.tr('navProfile')),
      ];
    } else if (user.isBarber) {
      tabs = const [
        BarberDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = [
        NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: context.tr('navMyDay')),
        NavigationDestination(
            icon: Badge(
              isLabelVisible: badge.unread > 0,
              label: Text('${badge.unread}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: context.tr('navChat')),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: context.tr('navProfile')),
      ];
    } else if (user.isOwner) {
      tabs = const [
        OwnerDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: context.tr('navOverview')),
        NavigationDestination(
            icon: Badge(
              isLabelVisible: badge.unread > 0,
              label: Text('${badge.unread}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: context.tr('navChat')),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: context.tr('navProfile')),
      ];
    } else {
      tabs = const [
        AdminDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = [
        NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings_rounded),
            label: context.tr('navAdmin')),
        NavigationDestination(
            icon: Badge(
              isLabelVisible: badge.unread > 0,
              label: Text('${badge.unread}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: context.tr('navChat')),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: context.tr('navProfile')),
      ];
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
