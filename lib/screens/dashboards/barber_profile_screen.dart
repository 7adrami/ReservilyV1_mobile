import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class BarberProfileScreen extends StatefulWidget {
  const BarberProfileScreen({super.key});

  @override
  State<BarberProfileScreen> createState() => _BarberProfileScreenState();
}

class _BarberProfileScreenState extends State<BarberProfileScreen> {
  String? _photo;
  final _specialty = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _specialty.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ShopService>().myBio();
      setState(() {
        _photo = data['photo'] as String?;
        _specialty.text = (data['specialty'] as String? ?? '');
        _bio.text = (data['bio'] as String? ?? '');
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<ShopService>().updateMyBio({
        'specialty': _specialty.text.trim(),
        'bio': _bio.text.trim(),
      });
      await _load();
      if (mounted) showMessage(context, 'Barber profile saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = context.read<ShopService>();
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      setState(() => _saving = true);
      await service.updateMyBio({}, photoBytes: bytes, photoFilename: file.name);
      await _load();
      messenger.showSnackBar(
          const SnackBar(content: Text('Profile photo updated.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: scheme.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Barber profile')),
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
            if (_loading && _specialty.text.isEmpty && _bio.text.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipOval(
                    child: AppPhoto(_photo,
                        borderRadius: 0, height: 120, fit: BoxFit.cover),
                  ),
                  InkWell(
                    onTap: _pickPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.photo_camera_rounded,
                          color: scheme.onPrimary, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Specialty',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AppField('Specialty', controller: _specialty),
            const SizedBox(height: 16),
            const Text('About me',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AppField('About me', controller: _bio, maxLines: 4),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save barber profile'),
            ),
          ],
        ),
      ),
    );
  }
}
