import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/reservation.dart';
import '../../models/shop.dart';
import '../../services/reservation_service.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

/// Booking form mirroring the Django site: pick a barber, then only the
/// services that barber offers, a date, a free time slot (booked slots are
/// locked, like the <select> on Django), and a payment panel listing the
/// barber's mobile money wallets so the customer can send the proof.
class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.slug,
    this.shop,
    this.initialBarberId,
  });

  final String slug;
  final Shop? shop;
  final int? initialBarberId;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  List<BookingBarber> _barbers = [];
  List<BookingService> _services = [];
  String? _error;
  bool _loadingOptions = true;

  BookingBarber? _barber;
  BookingService? _service;
  DateTime _date = DateTime.now();
  Availability? _availability;
  bool _loadingSlots = false;
  String? _selectedTime;

  XFile? _proof;
  Uint8List? _proofBytes;
  final _notes = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _loadingOptions = true);
    try {
      final shopService = context.read<ShopService>();
      final requestedId = widget.initialBarberId;
      final options = await shopService.bookingOptions(
        widget.slug,
        barber: requestedId,
      );
      if (!mounted) return;
      final requested = requestedId == null
          ? null
          : options.barbers.where((b) => b.pk == requestedId).firstOrNull;
      if (requested != null) {
        setState(() {
          _barbers = options.barbers;
          _services = options.services;
          _barber = requested;
          _loadingOptions = false;
        });
        await _loadAvailability();
      } else if (options.barbers.isNotEmpty) {
        setState(() {
          _barbers = options.barbers;
          _loadingOptions = false;
        });
        await _selectBarber(options.barbers.first);
      } else {
        setState(() {
          _barbers = [];
          _services = [];
          _loadingOptions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loadingOptions = false;
        });
      }
    }
  }

  /// Picks a barber and refetches ONLY that barber's services, like the
  /// Django form refills its service dropdown when you change the barber.
  Future<void> _selectBarber(BookingBarber? b) async {
    setState(() {
      _barber = b;
      _service = null;
      _services = [];
      _availability = null;
      _selectedTime = null;
    });
    if (b == null) return;
    try {
      final options = await context
          .read<ShopService>()
          .bookingOptions(widget.slug, barber: b.pk);
      if (!mounted) return;
      setState(() => _services = options.services);
      await _loadAvailability();
    } catch (_) {
      if (mounted) setState(() => _services = []);
    }
  }

  Future<void> _loadAvailability() async {
    final barber = _barber;
    if (barber == null) return;
    setState(() {
      _loadingSlots = true;
      _selectedTime = null;
    });
    try {
      final availability = await context
          .read<ReservationService>()
          .availability(
            barberId: barber.pk,
            date: _date,
            shopSlug: widget.slug,
            serviceId: _service?.pk,
          );
      if (!mounted) return;
      setState(() {
        _availability = availability;
        _loadingSlots = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _availability = null;
          _loadingSlots = false;
        });
      }
    }
  }

  Future<void> _pickProof() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!ReservationService.proofAllowed(bytes.length)) {
      if (mounted) showError(context, 'Payment proof is too large (max 8 MB).');
      return;
    }
    if (mounted) {
      setState(() {
        _proof = file;
        _proofBytes = bytes;
      });
    }
  }

  void _copyWallet(String value) {
    Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$value copied — send the payment proof to this wallet.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _submit() async {
    final barber = _barber;
    final service = _service;
    final time = _selectedTime;
    final bytes = _proofBytes;
    final proofName = _proof?.name ?? 'proof.jpg';
    if (barber == null || service == null || time == null || bytes == null) {
      showError(context, 'Complete every step first.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final reservation = await context.read<ReservationService>().create(
            shopSlug: widget.slug,
            barberId: barber.pk,
            serviceId: service.pk,
            date: _date,
            startTime: time,
            paymentProofBytes: bytes,
            paymentProofName: proofName,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      showMessage(
          context,
          'Booked with ${reservation.barberName} on '
          '${DateFormat('EEE, MMM d').format(reservation.date)} at '
          '${reservation.startTime} (ref #${reservation.id}).');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final barber = _barber;
    return Scaffold(
      appBar: AppBar(
        title: Text(barber == null
            ? 'Book · ${shop?.name ?? 'Barbershop'}'
            : 'Book with ${barber.name.split(' ').first}'),
      ),
      body: _error != null
          ? MessageView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load booking options',
              subtitle: _error,
              onRetry: _loadOptions,
            )
          : _loadingOptions
              ? const LoadingView()
              : _buildFlow(),
      bottomNavigationBar: _loadingOptions || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm booking'),
                ),
              ),
            ),
    );
  }

  Widget _buildFlow() {
    final barber = _barber;
    final service = _service;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Section(
          title: '1 · Choose a barber',
          child: _barbers.isEmpty
              ? const Text('No barbers available.')
              : DropdownButtonFormField<BookingBarber>(
                  value: barber,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Barber',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final b in _barbers)
                      DropdownMenuItem(
                        value: b,
                        child: Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (b) => _selectBarber(b),
                ),
        ),
        _Section(
          title: '2 · Choose a service',
          child: barber == null
              ? const Text('Pick a barber first — services are per barber.')
              : _services.isEmpty
                  ? const Text('This barber offers no services yet.')
                  : DropdownButtonFormField<BookingService>(
                      value: service,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Service',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in _services)
                          DropdownMenuItem(
                            value: s,
                            child: Text(
                              '${s.name} — ${money(s.price)} · '
                              '${s.durationMinutes} min',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (s) {
                        setState(() => _service = s);
                        _loadAvailability();
                      },
                    ),
        ),
        _Section(
          title: '3 · Pick a date',
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                  helpText: 'Pick the appointment date',
                );
                if (picked == null || !mounted) return;
                setState(() => _date = picked);
                _loadAvailability();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('EEEE, MMMM d, y').format(_date),
                      style: const TextStyle(fontSize: 15.5),
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_calendar_outlined, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Section(
          title: '4 · Pick a time',
          child: _loadingSlots
              ? const Padding(
                  padding: EdgeInsets.all(20), child: LoadingView())
              : _availability == null
                  ? const Text('No slots available this day.')
                  : DropdownButtonFormField<String>(
                      value: _selectedTime,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Available times',
                        border: OutlineInputBorder(),
                      ),
                      items: _availability!.slots.any((s) => s.open)
                          ? [
                              for (final slot in _availability!.slots)
                                DropdownMenuItem(
                                  value: slot.time,
                                  enabled: slot.open,
                                  child: Row(
                                    children: [
                                      Text(slot.time),
                                      if (!slot.open) ...[
                                        const SizedBox(width: 8),
                                        const Text('— Booked',
                                            style: TextStyle(
                                                color: Colors.redAccent,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ],
                                    ],
                                  ),
                                ),
                            ]
                          : const [],
                      onChanged: (t) => setState(() => _selectedTime = t),
                      hint: _availability == null ||
                              !_availability!.slots.any((s) => s.open)
                          ? const Text('Fully booked this day.')
                          : const Text('Select a time'),
                    ),
        ),
        _Section(
          title: '5 · Send payment',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (barber != null)
                ..._walletPanel(barber, service),
              OutlinedButton.icon(
                onPressed: _pickProof,
                icon: Icon(_proof == null
                    ? Icons.add_photo_alternate_outlined
                    : Icons.check_circle_outline_rounded),
                label: Text(_proof == null
                    ? 'Upload payment proof (photo)'
                    : _proof!.name),
              ),
              if (_proof != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                        _proofBytes!,
                        height: 160,
                        fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ),
        _Section(
          title: '6 · Notes (optional)',
          child: AppField(
            'Notes',
            controller: _notes,
            maxLines: 3,
          ),
        ),
      ],
    );
  }

  List<Widget> _walletPanel(BookingBarber barber, BookingService? service) {
    final serviceAmount =
        service?.price == null || service!.price! <= 0 ? null : service.price!;
    return [
      if (serviceAmount != null)
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Send '
                    '${money(serviceAmount)} '
                    'to ${barber.name.split(' ').first} for '
                    '${_service!.name}.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (barber.wallets.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('This barber has not set a wallet yet. Pay at the shop.'),
        )
      else ...[
        for (final w in barber.wallets) _WalletRow(wallet: w, onCopy: _copyWallet),
        const SizedBox(height: 10),
      ],
    ];
  }
}

/// Strips the +222 country code and any formatting from a wallet phone
/// number, returning the local 8-digit form customers use to send payment.
String walletPhoneDigits(String raw) {
  var text = raw.trim();
  if (text.startsWith('+222')) text = text.substring(4);
  return text.replaceAll(RegExp(r'\D'), '');
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.wallet, required this.onCopy});

  final Map<String, String> wallet;
  final void Function(String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final phone = wallet['phone'] ?? '';
    final digits = walletPhoneDigits(phone);
    final name = wallet['provider'] != null && wallet['provider']!.isNotEmpty
        ? wallet['provider']!
        : (wallet['name']?.isNotEmpty == true ? wallet['name']! : wallet['key'] ?? 'wallet');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(name),
        subtitle: Text(digits.isEmpty ? phone : digits),
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: 'Copy wallet number',
          onPressed: (digits.isEmpty ? phone : digits).isEmpty
              ? null
              : () => onCopy(digits.isEmpty ? phone : digits),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}