import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/shop.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  List<Shop>? _shops;
  List<String> _cities = [];
  String? _error;
  String _query = '';
  String? _city;
  double? _lat;
  double? _lng;
  bool _mapView = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final shopService = context.read<ShopService>();
    final cities = await shopService.cities();
    final shops = await shopService.listShops(
      query: _query.isEmpty ? null : _query,
          city: _city,
          lat: _lat,
          lng: _lng,
        );
    if (!mounted) return;
    setState(() {
      _shops = shops;
      _cities = cities;
    });
  }

  Future<void> _useMyLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final req = await Geolocator.requestPermission();
      if (req == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _city = null;
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  void _onQueryChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find your barber'),
        actions: [
          if (_lat != null && _lng != null)
            IconButton(
              tooltip: 'Clear location',
              onPressed: () {
                setState(() => _lat = _lng = null);
                _load();
              },
              icon: const Icon(Icons.location_off_outlined),
            ),
          IconButton(
            tooltip: 'Use my location',
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: _mapView ? 'List view' : 'Map view',
            onPressed: () => setState(() => _mapView = !_mapView),
            icon: Icon(_mapView ? Icons.list_rounded : Icons.map_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search shops, cities or streets',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CityChip(label: 'All', selected: _city == null, onTap: () {
                  setState(() => _city = null);
                  _load();
                }),
                ..._cities.map((c) {
                  final selected = _city == c;
                  return _CityChip(
                    label: c,
                    selected: selected,
                    onTap: () {
                      setState(() => _city = c);
                      _load();
                    },
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return MessageView(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load barbershops',
        subtitle: _error,
        onRetry: _load,
      );
    }
    final shops = _shops;
    if (shops == null) return const LoadingView();
    if (shops.isEmpty) {
      return const MessageView(
        icon: Icons.search_off_rounded,
        title: 'No barbershops found',
        subtitle: 'Try a different search or city.',
      );
    }
    if (_mapView) {
      return _MapView(shops: shops);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: shops.length,
        itemBuilder: (context, index) => _ShopCard(shop: shops[index]),
      ),
    );
  }
}

class _CityChip extends StatelessWidget {
  const _CityChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap?.call(),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/shop/${shop.slug}'),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: AppPhoto(shop.photo, borderRadius: 0),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 15, color: AppTheme.brand),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              '${shop.city} · ${shop.address}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 15, color: AppTheme.gold),
                          const SizedBox(width: 3),
                          Text(
                            '${shop.opensAt} – ${shop.closesAt}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          StarRating(shop.averageRating, size: 14),
                        ],
                      ),
                      if (shop.distanceKm != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${shop.distanceKm!.toStringAsFixed(1)} km away',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.shops});

  final List<Shop> shops;

  @override
  Widget build(BuildContext context) {
    final lat = shops
        .map((s) => s.latitude)
        .reduce((a, b) => (a + b) / 2);
    final lng = shops
        .map((s) => s.longitude)
        .reduce((a, b) => (a + b) / 2);
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: 9,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.reservily.app',
        ),
        MarkerLayer(
          markers: [
            for (final shop in shops)
              Marker(
                point: LatLng(shop.latitude, shop.longitude),
                width: 90,
                height: 48,
                child: GestureDetector(
                  onTap: () => context.push('/shop/${shop.slug}'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: Text(
                          shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.location_pin,
                          color: AppTheme.brand, size: 28),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
