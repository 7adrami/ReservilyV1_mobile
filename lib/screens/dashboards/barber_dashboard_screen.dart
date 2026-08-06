import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/reservation.dart';
import '../../services/reservation_service.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberDashboardScreen extends StatefulWidget {
  const BarberDashboardScreen({super.key});

  @override
  State<BarberDashboardScreen> createState() => _BarberDashboardScreenState();
}

class _BarberDashboardScreenState extends State<BarberDashboardScreen> {
  List<Reservation> _today = [];
  List<Reservation> _upcoming = [];
  String _todayLabel = '';
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
      final data = await context.read<ShopService>().barberDashboard();
      final todayStr = data['today'] as String? ?? '';
      final all = (data['upcoming'] as List<dynamic>? ?? [])
          .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _today = all.where((r) => r.date.toIso8601String().substring(0, 10) == todayStr).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        _upcoming = all.where((r) => r.date.toIso8601String().substring(0, 10) != todayStr).toList();
        _todayLabel = todayStr;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Reservation r, String status) async {
    try {
      await context.read<ReservationService>().setStatus(r.id, status);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _today.where((r) => r.isPending).length;
    final confirmed = _today.where((r) => r.isConfirmed).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Barber dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            if (_loading && _today.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            Row(
              children: [
                _StatCard(
                    icon: Icons.event_available,
                    label: 'Today',
                    value: '${_today.length}',
                    color: scheme.primary),
                _StatCard(
                    icon: Icons.schedule,
                    label: 'Pending',
                    value: '$pending',
                    color: scheme.tertiary),
                _StatCard(
                    icon: Icons.check_circle_outline,
                    label: 'Confirmed',
                    value: '$confirmed',
                    color: scheme.secondary),
              ],
            ),
            const SizedBox(height: 20),
            Text(_todayLabel.isEmpty ? 'Today' : 'Today · ${_fmtDay(_todayLabel)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_today.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No reservations today.')),
              ),
            ..._today.map((r) => _ReservationTile(
                  r: r,
                  onConfirm: r.isPending ? () => _setStatus(r, 'confirmed') : null,
                  onComplete: r.isActive ? () => _setStatus(r, 'completed') : null,
                  onCancel: r.isActive ? () => _setStatus(r, 'cancelled') : null,
                )),
            const SizedBox(height: 20),
            const Text('Upcoming',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_upcoming.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No upcoming reservations.')),
              ),
            ..._upcoming.map((r) => _ReservationTile(r: r)),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Manage my barbershop tools'),
                subtitle: const Text('Hours, services, requests, wallets'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/barber/hours'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDay(String iso) {
    try {
      return DateFormat.MMMMd().format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
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

class _ReservationTile extends StatelessWidget {
  const _ReservationTile(
      {required this.r,
      this.onConfirm,
      this.onComplete,
      this.onCancel});

  final Reservation r;
  final VoidCallback? onConfirm;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday =
        onConfirm != null || onComplete != null || onCancel != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isToday ? r.startTime : '${_shortDate(r.date)} · ${r.startTime}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer),
                  ),
                ),
                const Spacer(),
                _StatusChip(status: r.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(r.customerName != '—' ? r.customerName : r.barberName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('${r.serviceName} · ${money(num.tryParse(r.servicePrice))}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            if (r.notes != null && r.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('“${r.notes}”',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ],
            if (onConfirm != null || onComplete != null || onCancel != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onConfirm != null)
                    FilledButton.tonalIcon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm'),
                    ),
                  if (onComplete != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: onComplete,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Complete'),
                    ),
                  ],
                  const Spacer(),
                  if (onCancel != null)
                    IconButton(
                      onPressed: onCancel,
                      icon: Icon(Icons.close_rounded,
                          color: scheme.error, size: 20),
                      tooltip: 'Cancel',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.day}/${d.month}';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, String label) = switch (status) {
      Reservation.statusPending => (
          scheme.tertiaryContainer, scheme.onTertiaryContainer, 'Pending'),
      Reservation.statusConfirmed => (
          scheme.secondaryContainer, scheme.onSecondaryContainer, 'Confirmed'),
      Reservation.statusCompleted => (
          scheme.primaryContainer, scheme.onPrimaryContainer, 'Completed'),
      Reservation.statusCancelled => (
          scheme.errorContainer, scheme.onErrorContainer, 'Cancelled'),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
