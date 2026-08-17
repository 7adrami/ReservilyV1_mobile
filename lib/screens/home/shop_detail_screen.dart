import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
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
  int _rating = 0;
  final TextEditingController _comment = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final shop = await context.read<ShopService>().shopDetail(widget.slug);
      if (mounted) {
        setState(() {
          _shop = shop;
          _rating = shop.myRating ?? 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _saveRating() async {
    if (_rating < 1) return;
    try {
      await context.read<ShopService>().rateShop(widget.slug, _rating);
      if (!mounted) return;
      showMessage(context, 'Thanks for your rating!');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _postComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() => _posting = true);
    try {
      await context.read<ShopService>().reviewShop(widget.slug, body);
      _comment.clear();
      if (!mounted) return;
      showMessage(context, 'Thanks for your comment!');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _posting = false);
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
    final isOwner = context.select<Session, bool>((s) => s.user?.isOwner ?? false);
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
                    _Card(
                      title: 'Rate this shop',
                      child: isOwner
                          ? Text(
                              'Barbershop owners can comment but cannot rate shops.',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _rating > 0
                                      ? 'Your rating: $_rating★ — you can change it below.'
                                      : 'Give your rating once.',
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                                const SizedBox(height: 8),
                                StarInput(value: _rating, onChanged: (v) {
                                  setState(() => _rating = v);
                                }),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _rating > 0 ? _saveRating : null,
                                  child: const Text('Save my rating'),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      title: 'Leave a comment',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You can add as many comments as you like.',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          const SizedBox(height: 10),
                          AppField(
                            'Your comment',
                            controller: _comment,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _posting ? null : _postComment,
                              icon: _posting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: const Text('Post comment'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Latest reviews'),
                    if (shop.reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No reviews yet.'),
                      )
                    else
                      ...shop.reviews.map((r) => ReviewTile(review: r)),
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
          onTap: () => context.push('/barbers/${barber.id}'),
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
                        'View profile · book · rate',
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
