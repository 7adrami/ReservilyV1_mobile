import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
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

    final List<Widget> tabs;
    final List<NavigationDestination> destinations;
    if (user.isCustomer) {
      tabs = [
        const ShopsScreen(),
        ReservationsScreen(onFindBarber: () => setState(() => _index = 0)),
        const ChatListScreen(),
        const ProfileScreen(),
      ];
      destinations = const [
        NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Explore'),
        NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Bookings'),
        NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile'),
      ];
    } else if (user.isBarber) {
      tabs = const [
        BarberDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = const [
        NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'My Day'),
        NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile'),
      ];
    } else if (user.isOwner) {
      tabs = const [
        OwnerDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = const [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview'),
        NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile'),
      ];
    } else {
      tabs = const [
        AdminDashboardScreen(),
        ChatListScreen(),
        ProfileScreen(),
      ];
      destinations = const [
        NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings_rounded),
            label: 'Admin'),
        NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile'),
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
