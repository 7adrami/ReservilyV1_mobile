import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/locale_controller.dart';
import '../../core/theme_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../auth/auth_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _pickAvatar() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (file == null) return;
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final bytes = await file.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      if (mounted) showError(context, 'Avatar too large (max 4 MB).');
      return;
    }
    setState(() => _busy = true);
    try {
      await auth.uploadAvatarBytes(bytes, file.name);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ctx = context;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx2) => AlertDialog(
        title: Text(context.tr('signOutTitle')),
        content: Text(context.tr('signOutBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: Text(context.tr('stay'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: Text(context.tr('signOut'))),
        ],
      ),
    );
    if (ok == true && ctx.mounted) {
      await ctx.read<AuthService>().logout();
      if (ctx.mounted) ctx.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthService, User?>((s) => s.session.user);
    if (user == null) return const SizedBox();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _busy ? null : _pickAvatar,
                    child: Stack(
                      children: [
                        AppAvatar(user.avatar, name: user.name, size: 76),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('@${user.username}',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13.5)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(context.tr('role_${user.role}'),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GroupTitle(context.tr('appearance')),
          const _ThemePicker(),
          _LanguagePicker(),
          _GroupTitle(context.tr('account')),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(context.tr('editProfile')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showEditProfile(user),
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(context.tr('changePassword')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPasswordChange(user),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(context.tr('changeEmail')),
            subtitle: Text(user.email ?? 'No email set'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showEmailChange(user),
          ),
          _GroupTitle(context.tr('support')),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: Text(context.tr('sendFeedback')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showFeedback,
          ),
          if (user.isBarber) ...[
            _GroupTitle(context.tr('barberTools')),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(context.tr('workingHours')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/hours'),
            ),
            ListTile(
              leading: const Icon(Icons.content_cut_rounded),
              title: Text(context.tr('servicesPrices')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/styles'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: Text(context.tr('shopsRequests')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/requests'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(context.tr('paymentWallets')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/wallets'),
            ),
          ],
          if (user.isOwner) ...[
            _GroupTitle(context.tr('myShop')),
            ListTile(
              leading: const Icon(Icons.store_rounded),
              title: Text(context.tr('manageShop')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/shop'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(context.tr('myTeam')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/team'),
            ),
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: Text(context.tr('joinRequests')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/requests'),
            ),
          ],
          if (user.isAdmin) ...[
            _GroupTitle(context.tr('administration')),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(context.tr('broadcasts')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/broadcasts'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(context.tr('createOwner')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/owners'),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withOpacity(0.4)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(context.tr('signOut')),
          ),
        ],
      ),
    );
  }

  void _showFeedback() {
    final message = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('feedbackTitle'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            AppField(
              context.tr('feedbackHint'),
              controller: message,
              maxLines: 5,
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                final text = message.text.trim();
                if (text.isEmpty) {
                  showMessage(context, context.tr('feedbackEmpty'));
                  return;
                }
                final ctx = context;
                Navigator.pop(ctx);
                try {
                  await ctx.read<AuthService>().submitFeedback(text);
                  if (ctx.mounted) showMessage(ctx, context.tr('feedbackSent'));
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
              child: Text(context.tr('feedbackSend')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfile(User user) {
    final firstName = TextEditingController(text: user.firstName ?? '');
    final lastName = TextEditingController(text: user.lastName ?? '');
    final phone = TextEditingController(text: user.phone ?? '');
    var waitingVisible = user.waitingListVisible;

    showModalBottomSheet<void>(
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
                Text(context.tr('editProfile'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                AppField('First name', controller: firstName),
                const SizedBox(height: 12),
                AppField('Last name', controller: lastName),
                const SizedBox(height: 12),
                AppField('Phone', controller: phone,
                    keyboardType: TextInputType.phone),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show my place in the waiting list'),
                  value: waitingVisible,
                  onChanged: (v) => setSheetState(() => waitingVisible = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final ctx = context;
                    Navigator.pop(ctx);
                    try {
                      await ctx.read<AuthService>().updateProfile(
                            firstName: firstName.text.trim(),
                            lastName: lastName.text.trim(),
                            phone: phone.text.trim(),
                            waitingListVisible: waitingVisible,
                          );
                      if (ctx.mounted) showMessage(ctx, 'Profile updated.');
                    } catch (e) {
                      if (ctx.mounted) showError(ctx, e);
                    }
                  },
                  child: Text(context.tr('saveChanges')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordChange(User user) {
    final code = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: _PasswordChangeSheet(
            codeController: code,
            password1Controller: p1,
            password2Controller: p2,
            email: user.email,
            auth: context.read<AuthService>(),
          ),
        ),
      ),
    );
  }

  void _showEmailChange(User user) {
    final email = TextEditingController();
    final code = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: _EmailChangeSheet(
            emailController: email,
            codeController: code,
            auth: context.read<AuthService>(),
          ),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('System')),
        ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light')),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark')),
      ],
      selected: {controller.mode},
      onSelectionChanged: (set) => controller.setMode(set.first),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker();

  static const List<(Locale, String)> _options = [
    (Locale('en'), 'English'),
    (Locale('fr'), 'Français'),
    (Locale('ar'), 'العربية'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocaleController>();
    return ListTile(
      leading: const Icon(Icons.language_rounded),
      title: Text(context.tr('language')),
      trailing: DropdownButton<Locale>(
        value: controller.locale,
        underline: const SizedBox.shrink(),
        items: [
          for (final o in _options)
            DropdownMenuItem(value: o.$1, child: Text(o.$2)),
        ],
        onChanged: (l) {
          if (l != null) controller.setLocale(l);
        },
      ),
    );
  }
}

/// Email change flow mirroring the Django web version: first send the code to
/// the new address, then enter it to confirm (with a dev-mode code display and
/// a resend option, exactly like the web verification page).
class _EmailChangeSheet extends StatefulWidget {
  const _EmailChangeSheet({
    required this.emailController,
    required this.codeController,
    required this.auth,
  });

  final TextEditingController emailController;
  final TextEditingController codeController;
  final AuthService auth;

  @override
  State<_EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<_EmailChangeSheet> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;
  String? _debugCode;

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final debugCode =
          await widget.auth.emailChangeSend(widget.emailController.text.trim());
      if (mounted) {
        setState(() {
          _step = 1;
          _debugCode = debugCode;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await widget.auth.emailChangeComplete(
        widget.emailController.text.trim(),
        widget.codeController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Email updated.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Change email',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (_step == 0) ...[
            AppField(
              'New email',
              controller: widget.emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Enter the new email address.';
                if (!value.contains('@')) return 'Enter a valid email address.';
                return null;
              },
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send verification code'),
            ),
          ] else ...[
            Text(
              'Enter the 6-digit code sent to '
              '${widget.emailController.text.trim()}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OtpField(controller: widget.codeController),
            if (_debugCode != null) ...[
              const SizedBox(height: 10),
              Text(
                'Development code: $_debugCode',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _busy ? null : _complete,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Confirm new email'),
            ),
            TextButton(
              onPressed: _busy ? null : _send,
              child: const Text('Resend code'),
            ),
            TextButton(
              onPressed: () {
                widget.codeController.clear();
                setState(() {
                  _step = 0;
                  _debugCode = null;
                });
              },
              child: const Text('Use a different email'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Password change flow mirroring the Django web version: first send the code,
/// then enter it along with the new password (with a dev-mode code display and
/// a resend option, exactly like the web verification page).
class _PasswordChangeSheet extends StatefulWidget {
  const _PasswordChangeSheet({
    required this.codeController,
    required this.password1Controller,
    required this.password2Controller,
    required this.email,
    required this.auth,
  });

  final TextEditingController codeController;
  final TextEditingController password1Controller;
  final TextEditingController password2Controller;
  final String? email;
  final AuthService auth;

  @override
  State<_PasswordChangeSheet> createState() => _PasswordChangeSheetState();
}

class _PasswordChangeSheetState extends State<_PasswordChangeSheet> {
  int _step = 0;
  bool _busy = false;
  String? _debugCode;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final debugCode = await widget.auth.passwordChangeSend();
      if (mounted) {
        setState(() {
          _step = 1;
          _debugCode = debugCode;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (widget.password1Controller.text != widget.password2Controller.text) {
      showError(context, 'The two passwords do not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.auth.passwordChangeComplete(
        code: widget.codeController.text.trim(),
        password1: widget.password1Controller.text,
        password2: widget.password2Controller.text,
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Password updated.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Change password',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('A code is sent to ${widget.email ?? 'your email'}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        if (_step == 0)
          ElevatedButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send verification code'),
          )
        else ...[
          OtpField(controller: widget.codeController),
          if (_debugCode != null) ...[
            const SizedBox(height: 10),
            Text(
              'Development code: $_debugCode',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary),
            ),
          ],
          const SizedBox(height: 14),
          PasswordField('New password',
              controller: widget.password1Controller),
          const SizedBox(height: 10),
          PasswordField('Confirm new password',
              controller: widget.password2Controller),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _busy ? null : _complete,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Update password'),
          ),
          TextButton(
            onPressed: _busy ? null : _send,
            child: const Text('Resend code'),
          ),
        ],
      ],
    );
  }
}
