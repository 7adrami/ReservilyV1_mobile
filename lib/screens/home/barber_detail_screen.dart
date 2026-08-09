import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/shop.dart';
import '../../services/shop_service.dart';
import '../../widgets/common.dart';

/// Barber profile page: services & prices, star rating, comments — mirrors
/// the Django barber page (`/barbers/<pk>/`). Reviews follow the barber even
/// when he migrates to another shop.
class BarberDetailScreen extends StatefulWidget {
  const BarberDetailScreen({super.key, required this.pk});

  final int pk;

  @override
  State<BarberDetailScreen> createState() => _BarberDetailScreenState();
}

class _BarberDetailScreenState extends State<BarberDetailScreen> {
  BarberItem? _barber;
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
      final barber = await context.read<ShopService>().barberDetail(widget.pk);
      if (!mounted) return;
      setState(() {
        _barber = barber;
        _rating = barber.myRating ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _saveRating() async {
    if (_rating < 1) return;
    try {
      await context.read<ShopService>().rateBarber(widget.pk, _rating);
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
      await context.read<ShopService>().reviewBarber(widget.pk, body);
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
    final barber = _barber;
    return Scaffold(
      appBar: AppBar(title: Text(barber?.name ?? 'Barber')),
      body: _error != null
          ? MessageView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load this barber',
              subtitle: _error,
              onRetry: _load,
            )
          : barber == null
              ? const LoadingView()
              : _content(barber),
    );
  }

  Widget _content(BarberItem b) {
    final isOwner = context.select<Session, bool>((s) => s.user?.isOwner ?? false);
    final primaryShop = b.shops.isEmpty ? null : b.shops.first;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              AppAvatar(b.photo ?? b.avatar, name: b.name, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    if (b.specialty != null && b.specialty!.isNotEmpty)
                      Text(
                        b.specialty!,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    const SizedBox(height: 4),
                    StarRating(b.averageRating, count: b.ratingCount),
                  ],
                ),
              ),
            ],
          ),
          if (b.bio != null && b.bio!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(b.bio!, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          if (b.shops.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Works at',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in b.shops)
                  ActionChip(
                    avatar: const Icon(Icons.storefront_rounded,
                        size: 16, color: AppTheme.brand),
                    label: Text(
                      s.city == null ? s.name : '${s.name} · ${s.city}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => context.push('/shop/${s.slug}'),
                  ),
              ],
            ),
          ],
          if (b.services.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionTitle('Services & prices'),
            const SizedBox(height: 6),
            for (final s in b.services) _ServiceRow(service: s),
          ],
          if (primaryShop != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.push(
                  '/shop/${primaryShop.slug}/book?barber=${b.id}'),
              icon: const Icon(Icons.event_available_rounded),
              label: Text('Book with ${b.name.split(' ').first}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _Card(
            title: 'Rate this barber',
            child: isOwner
                ? Text(
                    'Barbershop owners can comment but cannot rate barbers.',
                    style: TextStyle(
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Post comment'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionTitle('Comments (${b.reviews.length})'),
          const SizedBox(height: 4),
          if (b.reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No comments yet — be the first!'),
            )
          else
            ...b.reviews.map((r) => ReviewTile(review: r)),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});

  final ServiceItem service;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(service.name,
                style: const TextStyle(fontSize: 14.5)),
          ),
          Text('${money(service.price)} · ${service.durationMinutes} min',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
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