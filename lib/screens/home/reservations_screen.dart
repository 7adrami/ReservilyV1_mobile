import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/reservation.dart';
import '../../services/reservation_service.dart';
import '../../widgets/common.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, this.onFindBarber});

  /// Switches the app to the Explore tab (when inside the home shell).
  final VoidCallback? onFindBarber;

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  List<Reservation>? _reservations;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await context.read<ReservationService>().list();
      if (mounted) setState(() => _reservations = list);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _cancel(Reservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
            '${r.barberName} on ${DateFormat('EEE, MMM d').format(r.date)} at ${r.startTime}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ReservationService>().cancel(r.id);
      await _load();
      if (mounted) showMessage(context, 'Booking cancelled.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: _error != null
          ? MessageView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your bookings',
              subtitle: _error,
              onRetry: _load,
            )
          : _reservations == null
              ? const LoadingView()
              : _reservations!.isEmpty
                  ? MessageView(
                      icon: Icons.event_busy_rounded,
                      title: 'No bookings yet',
                      subtitle:
                          'Find a barbershop on the Explore tab and book an appointment.',
                      onRetry: widget.onFindBarber,
                      retryLabel: 'Find a barbershop',
                      retryIcon: Icons.storefront_rounded,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reservations!.length,
                        itemBuilder: (context, index) {
                          final r = _reservations![index];
                          return _BookingCard(
                            reservation: r,
                            onCancel: r.canCancel ? () => _cancel(r) : null,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.reservation, this.onCancel});

  final Reservation reservation;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = reservation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(scheme, r.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(scheme, r.status),
                    ),
                  ),
                ),
                const Spacer(),
                Text('#${r.id}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Text(r.shopName,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${DateFormat('EEEE, MMM d, yyyy').format(r.date)} · ${r.startTime}'
              '${r.endTime != null ? '–${r.endTime}' : ''}',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text('${r.barberName} · ${r.serviceName}',
                style: const TextStyle(fontSize: 14)),
            Text('${money(double.tryParse(r.servicePrice))} · ${r.city}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            if (r.isActive && r.position != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.airline_seat_recline_normal_rounded,
                        size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Position ${r.position} in queue'
                      '${r.waitMinutes != null ? ' · ~${r.waitMinutes} min wait' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: const Size(0, 42),
                    side: BorderSide(color: scheme.error.withOpacity(0.4)),
                  ),
                  child: const Text('Cancel booking'),
                ),
              ),
            ],
            if (r.shopSlug != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/shop/${r.shopSlug}/book'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                      icon: const Icon(Icons.event_available_rounded,
                          size: 18),
                      label: const Text('Book again'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'View shop',
                    onPressed: () => context.push('/shop/${r.shopSlug}'),
                    icon: const Icon(Icons.storefront_outlined, size: 20),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme scheme, String status) {
    switch (status) {
      case Reservation.statusPending:
        return scheme.tertiary;
      case Reservation.statusConfirmed:
        return scheme.primary;
      case Reservation.statusCompleted:
        return Colors.green;
      case Reservation.statusCancelled:
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }
}
