import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/constants.dart';
import '../core/theme.dart';

/// Resolves API-relative media paths (e.g. `/media/shops/x.png`) against the
/// configured backend so CachedNetworkImage can load them on any platform.
String? mediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) return '${AppConfig.baseUrl}$url';
  return url;
}

String money(num? value) {
  final v = (value ?? 0).toDouble();
  final whole = v % 1 == 0;
  return '${whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} '
      '${AppConfig.currency}';
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    final first = parts.first[0];
    return first.toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// Round avatar with network image + initials fallback.
class AppAvatar extends StatelessWidget {
  const AppAvatar(this.url, {super.key, this.name = '', this.size = 44});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = mediaUrl(url);
    final child = resolved == null
        ? _Initials(name: name, size: size)
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: resolved,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => _Initials(name: name, size: size),
              errorWidget: (_, __, ___) => _Initials(name: name, size: size),
            ),
          );
    return SizedBox(width: size, height: size, child: child);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.brand, AppTheme.brandAccent],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name.isEmpty ? '?' : name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Photo banner (square-ish rounded) with graceful fallback.
class AppPhoto extends StatelessWidget {
  const AppPhoto(this.url, {super.key, this.borderRadius = 20, this.height});

  final String? url;
  final double borderRadius;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolved = mediaUrl(url);
    final shape = BorderRadius.circular(borderRadius);
    Widget child;
    if (resolved == null) {
      child = Container(
        color: AppTheme.brandLight.withOpacity(0.5),
        alignment: Alignment.center,
        child: const Icon(Icons.content_cut_rounded,
            size: 56, color: AppTheme.brand),
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: resolved,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppTheme.brandLight.withOpacity(0.5),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: AppTheme.brandLight.withOpacity(0.5),
          alignment: Alignment.center,
          child: const Icon(Icons.content_cut_rounded,
              size: 56, color: AppTheme.brand),
        ),
      );
    }
    return ClipRRect(borderRadius: shape, child: SizedBox(height: height, child: child));
  }
}

/// Standard loading placeholder.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.tint = AppTheme.brand});
  final Color tint;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 3, color: tint),
        ),
      );
}

/// Standard error / empty state with retry.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.title,
    this.message,
    this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String? title;
  final String? message;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 14),
            Text(title ?? message ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant)),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded, labeled text field matching the app theme.
class AppField extends StatelessWidget {
  const AppField(
    this.label, {
    super.key,
    this.controller,
    this.obscure = false,
    this.keyboardType,
    this.icon,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
    this.suffix,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? icon;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Widget? suffix;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      maxLines: maxLines,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Error message extraction helper.
String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  if (error is String) return error;
  return error.toString();
}

/// Shows a floating snackbar with the friendly error.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Section header used on detail screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.actionLabel});

  final String title;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (action != null)
          TextButton(onPressed: action, child: Text(actionLabel ?? 'View all')),
      ],
    );
  }
}

/// Star rating display (filled for [rating], empty otherwise).
class StarRating extends StatelessWidget {
  const StarRating(this.rating, {super.key, this.size = 18, this.count});

  final double? rating;
  final double size;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final r = rating ?? 0;
    const color = AppTheme.gold;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            r >= i
                ? Icons.star_rounded
                : (r >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: color,
          ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            '${r.toStringAsFixed(1)} ($count)',
            style: TextStyle(
              fontSize: size * 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
