import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class OwnerShopScreen extends StatefulWidget {
  const OwnerShopScreen({super.key});

  @override
  State<OwnerShopScreen> createState() => _OwnerShopScreenState();
}

class _OwnerShopScreenState extends State<OwnerShopScreen> {
  Map<String, dynamic>? _shop;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().ownerShop();
      _shop = data['shop'] as Map<String, dynamic>?;
      _error = null;
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final s = _shop;
    if (s == null) return;
    final name = TextEditingController(text: s['name'] as String? ?? '');
    final address = TextEditingController(text: s['address'] as String? ?? '');
    final city = TextEditingController(text: s['city'] as String? ?? '');
    final phone = TextEditingController(text: s['phone'] as String? ?? '');
    final description = TextEditingController(text: s['description'] as String? ?? '');
    final opensAt = TextEditingController(text: s['opens_at'] as String? ?? '09:00');
    final closesAt = TextEditingController(text: s['closes_at'] as String? ?? '21:30');
    var active = s['is_active'] != false;
    List<int>? photoBytes;
    String? photoName;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Shop details',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                AppField('Name', controller: name),
                const SizedBox(height: 12),
                AppField('Address', controller: address),
                const SizedBox(height: 12),
                AppField('City', controller: city),
                const SizedBox(height: 12),
                AppField('Phone', controller: phone,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                AppField('Description', controller: description,
                    maxLines: 3),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppField('Opens', controller: opensAt),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppField('Closes', controller: closesAt),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shop is open for bookings'),
                  value: active,
                  onChanged: (v) => setSheetState(() => active = v),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1600,
                        maxHeight: 1600);
                    if (file != null) {
                      final bytes = await file.readAsBytes();
                      setSheetState(() {
                        photoBytes = bytes;
                        photoName = file.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.photo_outlined),
                  label: Text(photoBytes == null ? 'Change shop photo' : 'Photo selected'),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<ShopService>().updateOwnerShop(
            {
              'name': name.text.trim(),
              'address': address.text.trim(),
              'city': city.text.trim(),
              'phone': phone.text.trim(),
              'description': description.text.trim(),
              'opens_at': opensAt.text.trim(),
              'closes_at': closesAt.text.trim(),
              'is_active': '$active',
            },
            photoBytes: photoBytes,
            photoFilename: photoName,
          );
      await _load();
      if (mounted) showMessage(context, 'Shop updated.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _shop;
    return Scaffold(
      appBar: AppBar(title: const Text('My barbershop')),
      floatingActionButton: s == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(_saving ? 'Saving…' : 'Edit details'),
            ),
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
                  height: 180, borderRadius: 16),
              const SizedBox(height: 16),
              Text(s['name'] as String,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${s['city']} · ${s['address']}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('Opens ${s['opens_at']} – ${s['closes_at']}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              if ((s['description'] as String? ?? '').isNotEmpty)
                Text(s['description'] as String),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text('${s['average_rating'] ?? '0.0'} '
                      '(${s['rating_count'] ?? 0} reviews)'),
                  const Spacer(),
                  if (s['is_active'] == false)
                    Chip(
                      avatar: Icon(Icons.pause_circle_outline,
                          size: 16, color: scheme.error),
                      label: const Text('Closed for bookings'),
                      backgroundColor: scheme.errorContainer,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
