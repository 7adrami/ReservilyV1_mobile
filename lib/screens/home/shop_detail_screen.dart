import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/shop.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

class ShopDetailScreen extends StatefulWidget {
  const ShopDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  Shop? _shop;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final shop = await context.read<ShopService>().shopDetail(widget.slug);
      if (mounted) setState(() => _shop = shop);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    return Scaffold(
      appBar: AppBar(title: Text(_shop?.name ?? 'Barbershop')),
      body: _error != null
          ? MessageView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load this shop',
              subtitle: _error,
              onRetry: _load,
            )
          : shop == null
              ? const LoadingView()
              : _content(shop),
    );
  }

  Widget _content(Shop shop) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppPhoto(shop.photo, height: 200),
                    const SizedBox(height: 16),
                    Text(shop.name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 18, color: AppTheme.brand),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${shop.city} · ${shop.address}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 18, color: AppTheme.gold),
                        const SizedBox(width: 4),
                        Text('Open ${shop.opensAt} – ${shop.closesAt}',
                            style: const TextStyle(fontSize: 14)),
                        const Spacer(),
                        StarRating(shop.averageRating,
                            count: shop.ratingCount),
                      ],
                    ),
                    if (shop.phone != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 18, color: AppTheme.brand),
                          const SizedBox(width: 4),
                          Text(shop.phone!, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ],
                    if (shop.description != null &&
                        shop.description!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(shop.description!,
                          style: TextStyle(
                              fontSize: 14, height: 1.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                    const SizedBox(height: 20),
                    const SectionTitle('Barbers'),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (shop.barbers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No barbers are working here yet.',
                      textAlign: TextAlign.center),
                )
              else
                ...shop.barbers.map(
                    (b) => _BarberTile(shopSlug: shop.slug, barber: b)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('Latest reviews'),
                    if (shop.reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No reviews yet.'),
                      )
                    else
                      ...shop.reviews.map((r) => _ReviewTile(review: r)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/shop/${shop.slug}/book'),
                  icon: const Icon(Icons.event_available_rounded),
                  label: const Text('Book an appointment'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () =>
                    openMapsDirections(shop.latitude, shop.longitude),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  padding: const EdgeInsets.all(0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Icon(Icons.directions_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarberTile extends StatelessWidget {
  const _BarberTile({required this.shopSlug, required this.barber});

  final String shopSlug;
  final BarberItem barber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context
              .push('/shop/$shopSlug/book?barber=${barber.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                AppAvatar(barber.avatar, name: barber.name, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(barber.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      if (barber.specialty != null &&
                          barber.specialty!.isNotEmpty)
                        Text(
                          barber.specialty!,
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      if (barber.services.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final s in barber.services)
                                Chip(
                                  label: Text(
                                    '${s.name} · ${money(s.price)}',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to book with ${barber.name.split(' ').first}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    StarRating(barber.averageRating, size: 15),
                    const SizedBox(height: 8),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final ReviewItem review;

  @override
  Widget build(BuildContext context) {
    final when = review.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(review.avatar, name: review.userName ?? '', size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(review.userName ?? '',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    if (when != null)
                      Text(
                        _fmt(when),
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(review.body ?? '',
                    style: const TextStyle(fontSize: 13.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
