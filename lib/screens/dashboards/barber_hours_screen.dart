import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberHoursScreen extends StatefulWidget {
  const BarberHoursScreen({super.key});

  @override
  State<BarberHoursScreen> createState() => _BarberHoursScreenState();
}

class _BarberHoursScreenState extends State<BarberHoursScreen> {
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String? _shopSlug;
  List<Map<String, dynamic>> _shops = [];
  final Map<int, ({String open, String close})> _schedule = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().barberRequests();
      final shops = (data['shops'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .toList();
      final myShops = (data['my_shops'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      setState(() => _shops = myShops.isNotEmpty ? myShops : shops);
      if (_shops.isNotEmpty) {
        _shopSlug ??= _shops.first['slug'] as String;
        await _loadSchedule();
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSchedule() async {
    if (_shopSlug == null) return;
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().barberHours(shopSlug: _shopSlug);
      _schedule.clear();
      for (final e in data['schedule'] as List<dynamic>? ?? []) {
        final m = e as Map<String, dynamic>;
        _schedule[m['weekday'] as int] =
            (open: m['opens_at'] as String, close: m['closes_at'] as String);
      }
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay(int day) async {
    final current = _schedule[day];
    final time = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : _parse(current.open),
      helpText: '${_days[day]} — opening time',
    );
    if (time == null) return;
    TimeOfDay close = current == null
        ? const TimeOfDay(hour: 17, minute: 0)
        : _parse(current.close);
    if (mounted) {
      final pickedClose = await showTimePicker(
        context: context,
        initialTime: close,
        helpText: '${_days[day]} — closing time',
      );
      if (pickedClose != null) close = pickedClose;
    }
    if (!mounted) return;
    setState(() {
      _schedule[day] = (open: _fmt(time), close: _fmt(close));
    });
  }

  void _clearDay(int day) {
    setState(() => _schedule.remove(day));
  }

  Future<void> _save() async {
    final entries = _schedule.entries
        .map((e) => {'weekday': e.key, 'opens_at': e.value.open, 'closes_at': e.value.close})
        .toList()
      ..sort((a, b) => (a['weekday'] as int).compareTo(b['weekday'] as int));
    setState(() => _saving = true);
    try {
      await context
          .read<ShopService>()
          .saveBarberHours(shopSlug: _shopSlug!, schedule: entries);
      if (mounted) showMessage(context, 'Working hours saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static TimeOfDay _parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Working hours')),
      body: RefreshIndicator(
        onRefresh: _loadShops,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              MessageView(message: _error!, onRetry: _loadShops),
              const SizedBox(height: 12),
            ],
            if (_shops.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _shopSlug,
                decoration: const InputDecoration(
                  labelText: 'Barbershop',
                  border: OutlineInputBorder(),
                ),
                items: _shops
                    .map((s) => DropdownMenuItem(
                        value: s['slug'] as String,
                        child: Text(s['name'] as String)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _shopSlug = v);
                  _loadSchedule();
                },
              ),
            const SizedBox(height: 16),
            if (_loading && _schedule.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            ..._days.indexed.map((entry) {
              final (day, label) = entry;
              final s = _schedule[day];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                      day < 5 ? Icons.work_outline : Icons.weekend_outlined,
                      color: s == null ? scheme.outline : scheme.primary),
                  title: Text(label),
                  subtitle: Text(s == null ? 'Day off' : '${s.open} – ${s.close}'),
                  trailing: s == null
                      ? TextButton(
                          onPressed: () => _pickDay(day), child: const Text('Set'))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _pickDay(day),
                              tooltip: 'Change hours',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: scheme.error),
                              onPressed: () => _clearDay(day),
                              tooltip: 'Day off',
                            ),
                          ],
                        ),
                ),
              );
            }),
            if (_shops.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save working hours'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
