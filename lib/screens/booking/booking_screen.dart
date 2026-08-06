import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/reservation.dart';
import '../../models/shop.dart';
import '../../services/reservation_service.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.slug, this.shop});

  final String slug;
  final Shop? shop;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  BookingOptions? _options;
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
      final options =
          await context.read<ShopService>().bookingOptions(widget.slug);
      if (!mounted) return;
      setState(() {
        _options = options;
        _loadingOptions = false;
        _barber ??= options.barbers.isNotEmpty ? options.barbers.first : null;
        _service ??= options.services.isNotEmpty ? options.services.first : null;
      });
      await _loadAvailability();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loadingOptions = false;
        });
      }
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
    return Scaffold(
      appBar: AppBar(title: Text('Book · ${shop?.name ?? 'Barbershop'}')),
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
    final options = _options!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Section(
          title: '1 · Choose a barber',
          child: options.barbers.isEmpty
              ? const Text('No barbers available.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in options.barbers)
                      ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Text(initialsOf(b.name),
                              style:
                                  const TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                        label: Text(b.name),
                        selected: _barber?.pk == b.pk,
                        onSelected: (_) {
                          setState(() => _barber = b);
                          _loadAvailability();
                        },
                      ),
                  ],
                ),
        ),
        _Section(
          title: '2 · Choose a service',
          child: options.services.isEmpty
              ? const Text('No services available.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in options.services)
                      ChoiceChip(
                        label: Text(
                            '${s.name} · ${s.durationMinutes} min'),
                        selected: _service?.pk == s.pk,
                        onSelected: (_) {
                          setState(() => _service = s);
                          _loadAvailability();
                        },
                      ),
                  ],
                ),
        ),
        _Section(
          title: '3 · Pick a date',
          child: Card(
            child: CalendarDatePicker(
              initialDate: _date,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              onDateChanged: (d) {
                setState(() => _date = d);
                _loadAvailability();
              },
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
                  : _availability!.slots.any((s) => s.open)
                      ? Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final slot in _availability!.slots)
                              if (slot.open)
                                ChoiceChip(
                                  label: Text(slot.time),
                                  selected: _selectedTime == slot.time,
                                  onSelected: (_) {
                                    setState(() =>
                                        _selectedTime = slot.time);
                                  },
                                ),
                          ],
                        )
                      : const Text('Fully booked this day.'),
        ),
        _Section(
          title: '5 · Payment proof & notes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 12),
              AppField(
                'Notes (optional)',
                controller: _notes,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ],
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
