import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_web/geolocator_web.dart'
    if (dart.library.io) 'package:reservily/stubs/web_geolocator_stub.dart'
    as web_geolocator;
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
  bool _locating = false;
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
    try {
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
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Fast location: races the device/browser GPS fix against an IP-based
  /// location, so "Near me" answers in well under a second whenever possible
  /// and can never hang (hard 5s cap).
  Future<Position> _locate() async {
    final completer = Completer<Position>();
    Future<void> track(Future<Position> candidate) async {
      try {
        final pos = await candidate;
        if (!completer.isCompleted) completer.complete(pos);
      } catch (_) {}
    }

    unawaited(track(_gpsFix()));
    unawaited(track(_ipLocation()));
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Location timed out'),
    );
  }

  /// Device/browser GPS fix: cached position first, then a short fresh fix.
  Future<Position> _gpsFix() async {
    if (kIsWeb) {
      return GeolocatorPlatform.instance.getCurrentPosition(
        locationSettings: web_geolocator.WebSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
          maximumAge: const Duration(minutes: 10),
        ),
      );
    }
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) return cached;
    } catch (_) {}
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 4),
    );
  }

  /// Approximate location from the IP address (~300ms, no permission needed).
  Future<Position> _ipLocation() async {
    for (final url in const [
      'https://ipapi.co/json/',
      'https://ipinfo.io/json',
    ]) {
      try {
        final resp = await Dio().get<Map<String, dynamic>>(
          url,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        final pos = _parseIpPosition(resp.data);
        if (pos != null) return pos;
      } catch (_) {}
    }
    throw const FormatException('IP location unavailable');
  }

  Position? _parseIpPosition(Map<String, dynamic>? data) {
    if (data == null) return null;
    double? lat;
    double? lng;
    final loc = data['loc'];
    if (loc is String) {
      final parts = loc.split(',');
      if (parts.length == 2) {
        lat = double.tryParse(parts[0].trim());
        lng = double.tryParse(parts[1].trim());
      }
    }
    lat ??= _asLatLng(data['latitude']) ?? _asLatLng(data['lat']);
    lng ??= _asLatLng(data['longitude']) ?? _asLatLng(data['lng']);
    if (lat == null || lng == null) return null;
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5000,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      floor: null,
      isMocked: false,
    );
  }

  double? _asLatLng(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!kIsWeb) {
        // Ask for GPS permission, but don't block on denial: the IP-based
        // fallback (which needs no permission) still lets "Near me" work.
        try {
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
        } catch (_) {}
      }
      final pos = await _locate();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _city = null;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      final message = e is PermissionDeniedException
          ? 'Location access is blocked. Allow location for this site in your browser or app settings, then try again.'
          : e is TimeoutException
              ? 'Could not determine your location. Check your internet connection and try again.'
              : 'Could not get your location: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
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
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
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
      return _MapView(
        shops: shops,
        userLat: _lat,
        userLng: _lng,
        onNearMe: _useMyLocation,
        locating: _locating,
      );
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
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () =>
                            openMapsDirections(shop.latitude, shop.longitude),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.directions_rounded, size: 16),
                        label: const Text('Get directions'),
                      ),
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

class _MapView extends StatefulWidget {
  const _MapView({
    required this.shops,
    this.userLat,
    this.userLng,
    this.onNearMe,
    this.locating = false,
  });

  final List<Shop> shops;
  final double? userLat;
  final double? userLng;
  final VoidCallback? onNearMe;
  final bool locating;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  final MapController _controller = MapController();
  bool _mapReady = false;
  bool _centeredOnUser = false;

  @override
  void didUpdateWidget(covariant _MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userLat = widget.userLat;
    final userLng = widget.userLng;
    if (userLat != null &&
        userLng != null &&
        (userLat != oldWidget.userLat || userLng != oldWidget.userLng)) {
      _recenterOnUser(LatLng(userLat, userLng));
    }
  }

  void _recenterOnUser(LatLng pos) {
    if (!_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.move(pos, 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userPos = (widget.userLat != null && widget.userLng != null)
        ? LatLng(widget.userLat!, widget.userLng!)
        : null;
    final shops = widget.shops;
    final lat = shops
        .map((s) => s.latitude)
        .reduce((a, b) => (a + b) / 2);
    final lng = shops
        .map((s) => s.longitude)
        .reduce((a, b) => (a + b) / 2);
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: userPos ?? LatLng(lat, lng),
            initialZoom: userPos != null ? 15 : 9,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            onMapReady: () {
              _mapReady = true;
              if (userPos != null && !_centeredOnUser) {
                _centeredOnUser = true;
                _controller.move(userPos, 15);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.reservily.app',
            ),
            if (userPos != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: userPos,
                    width: 40,
                    height: 40,
                    child: _UserDot(),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final shop in shops)
                  Marker(
                    point: LatLng(shop.latitude, shop.longitude),
                    width: 90,
                    height: 52,
                    child: GestureDetector(
                      onTap: () => _openShopSheet(context, shop, userPos),
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
        ),
        if (widget.onNearMe != null)
          Positioned(
            right: 12,
            bottom: 20,
            child: FloatingActionButton.extended(
              heroTag: 'near-me',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              onPressed: widget.onNearMe,
              icon: widget.locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(widget.locating ? 'Locating…' : 'Near me'),
            ),
          ),
      ],
    );
  }

  void _openShopSheet(BuildContext context, Shop shop, LatLng? userPos) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppPhoto(shop.photo,
                      borderRadius: 14, height: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('${shop.city} · ${shop.address}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        if (shop.distanceKm != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${shop.distanceKm!.toStringAsFixed(1)} km away',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _goDirections(shop.latitude, shop.longitude, userPos);
                      },
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Get directions'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/shop/${shop.slug}');
                      },
                      icon: const Icon(Icons.storefront_rounded),
                      label: const Text('View shop'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goDirections(
      double lat, double lng, LatLng? userPos) async {
    try {
      await openMapsDirections(
        lat,
        lng,
        originLat: userPos?.latitude,
        originLng: userPos?.longitude,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

class _UserDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
