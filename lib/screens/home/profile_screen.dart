import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme_controller.dart';
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
    final bytes = await file.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      if (mounted) showError(context, 'Avatar too large (max 4 MB).');
      return;
    }
    setState(() => _busy = true);
    final ctx = context;
    final uploadAvatarBytes = ctx.read<AuthService>().uploadAvatarBytes;
    try {
      await uploadAvatarBytes(bytes, file.name);
    } catch (e) {
      if (ctx.mounted) showError(ctx, e);
    } finally {
      if (ctx.mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ctx = context;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx2) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Sign out')),
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
      appBar: AppBar(title: const Text('Profile')),
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
                          child: Text(_roleLabel(user.role),
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
          const _GroupTitle('Appearance'),
          const _ThemePicker(),
          const _GroupTitle('Account'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Edit profile'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showEditProfile(user),
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPasswordChange(user),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: const Text('Change email'),
            subtitle: Text(user.email ?? 'No email set'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showEmailChange(user),
          ),
          if (user.isBarber) ...[
            const _GroupTitle('Barber tools'),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Working hours'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/hours'),
            ),
            ListTile(
              leading: const Icon(Icons.content_cut_rounded),
              title: const Text('My services & prices'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/styles'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: const Text('Shops & requests'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/requests'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Payment wallets'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/barber/wallets'),
            ),
          ],
          if (user.isOwner) ...[
            const _GroupTitle('My barbershop'),
            ListTile(
              leading: const Icon(Icons.store_rounded),
              title: const Text('Manage shop details'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/shop'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('My team'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/team'),
            ),
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Join / leave requests'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/owner/requests'),
            ),
          ],
          if (user.isAdmin) ...[
            const _GroupTitle('Administration'),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Broadcasts'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/broadcasts'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Create shop owner'),
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
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case User.roleCustomer:
        return 'Customer';
      case User.roleBarber:
        return 'Barber';
      case User.roleOwner:
        return 'Shop owner';
      case User.roleAdmin:
        return 'Administrator';
      default:
        return role;
    }
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
                const Text('Edit profile',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
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
                  child: const Text('Save changes'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change password',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('A code is sent to ${user.email ?? 'your email'}',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              OtpField(controller: code),
              const SizedBox(height: 14),
              PasswordField('New password', controller: p1),
              const SizedBox(height: 10),
              PasswordField('Confirm new password', controller: p2),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () async {
                  final auth = context.read<AuthService>();
                  try {
                    if (p1.text != p2.text) {
                      showError(context, 'The two passwords do not match.');
                      return;
                    }
                    await auth.passwordChangeComplete(
                      code: code.text.trim(),
                      password1: p1.text,
                      password2: p2.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      showMessage(context, 'Password updated.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Update password'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await context.read<AuthService>().passwordChangeSend();
                    if (context.mounted) {
                      showMessage(context, 'Verification code sent to your email.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Send verification code'),
              ),
            ],
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change email',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              AppField('New email', controller: email,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 14),
              OtpField(controller: code),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () async {
                  final auth = context.read<AuthService>();
                  try {
                    await auth.emailChangeComplete(
                        email.text.trim(), code.text.trim());
                    if (context.mounted) {
                      Navigator.pop(context);
                      showMessage(context, 'Email updated.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Confirm new email'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await context
                        .read<AuthService>()
                        .emailChangeSend(email.text.trim());
                    if (context.mounted) {
                      showMessage(
                          context, 'Verification code sent to the new email.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Send verification code'),
              ),
            ],
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
