import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_web/geolocator_web.dart'
    if (dart.library.io) 'package:reservily/stubs/web_geolocator_stub.dart'
    as web_geolocator;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
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

  static const double _defaultLat = 18.0859;
  static const double _defaultLng = -15.9785;

  Future<Position> _currentPosition() async {
    if (kIsWeb) {
      return GeolocatorPlatform.instance.getCurrentPosition(
        locationSettings: web_geolocator.WebSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 6),
        ),
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission is permanently denied. Enable it in settings.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 8),
    );
  }

  Future<void> _edit() async {
    final scheme = Theme.of(context).colorScheme;
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
    double lat = (s['latitude'] as num?)?.toDouble() ?? _defaultLat;
    double lng = (s['longitude'] as num?)?.toDouble() ?? _defaultLng;
    final mapController = MapController();
    var locating = false;
    var reverseGeocoding = false;
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
                const SizedBox(height: 14),
                const Text('Location',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 180,
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: LatLng(lat, lng),
                        initialZoom: 15,
                        onTap: (_, point) {
                          setSheetState(() {
                            lat = point.latitude;
                            lng = point.longitude;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.reservily.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 40,
                              height: 40,
                              child: Icon(Icons.location_pin,
                                  color: scheme.primary, size: 40),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: locating
                            ? null
                            : () async {
                                setSheetState(() => locating = true);
                                try {
                                  final pos = await _currentPosition();
                                  setSheetState(() {
                                    lat = pos.latitude;
                                    lng = pos.longitude;
                                  });
                                  mapController.move(LatLng(lat, lng), 15);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                } finally {
                                  if (mounted) {
                                    setSheetState(() => locating = false);
                                  }
                                }
                              },
                        icon: locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(locating ? 'Locating…' : 'Use my location'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: reverseGeocoding
                            ? null
                            : () async {
                                setSheetState(() => reverseGeocoding = true);
                                try {
                                  final resp = await Dio().get<Map<String, dynamic>>(
                                    'https://nominatim.openstreetmap.org/reverse',
                                    queryParameters: {
                                      'format': 'jsonv2',
                                      'lat': '$lat',
                                      'lon': '$lng',
                                    },
                                    options: Options(
                                      responseType: ResponseType.json,
                                      receiveTimeout: const Duration(seconds: 12),
                                    ),
                                  );
                                  final display =
                                      resp.data?['display_name'] as String?;
                                  if (display == null || display.isEmpty) {
                                    throw Exception(
                                        'No address found for this location.');
                                  }
                                  final parts = display.split(',');
                                  if (parts.length > 1) parts.removeLast();
                                  final addr =
                                      resp.data?['address'] as Map<String, dynamic>?;
                                  final place = addr?['city'] ??
                                      addr?['town'] ??
                                      addr?['village'] ??
                                      addr?['state'];
                                  final cityName =
                                      place is String ? place : (place?.toString() ?? '');
                                  setSheetState(() {
                                    address.text = parts.join(',').trim();
                                    if (cityName.isNotEmpty) {
                                      city.text = cityName;
                                    }
                                  });
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                } finally {
                                  if (mounted) {
                                    setSheetState(() => reverseGeocoding = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.map_rounded),
                        label: Text(reverseGeocoding
                            ? 'Getting address…'
                            : 'Fill address from map'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Tap the map to set the exact location.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
              'latitude': '$lat',
              'longitude': '$lng',
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
