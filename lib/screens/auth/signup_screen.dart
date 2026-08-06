import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _step = 0;
  bool _busy = false;

  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _password1 = TextEditingController();
  final _password2 = TextEditingController();

  String? _debugCode;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _code.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _password1.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final code = await context
          .read<AuthService>()
          .signupSend(_username.text.trim(), _email.text.trim());
      if (mounted) {
        setState(() {
          _step = 1;
          _debugCode = code;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().signupComplete(
            username: _username.text.trim(),
            email: _email.text.trim(),
            code: _code.text.trim(),
            password1: _password1.text,
            password2: _password2.text,
            firstName: _firstName.text.trim().isEmpty
                ? null
                : _firstName.text.trim(),
            lastName: _lastName.text.trim().isEmpty
                ? null
                : _lastName.text.trim(),
          );
      if (mounted) {
        showMessage(context, 'Welcome to Reservily!');
        context.go('/');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Stepper(current: _step),
                    const SizedBox(height: 24),
                    if (_step == 0) _stepOne(),
                    if (_step == 1) _stepTwo(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepOne() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          'Username',
          controller: _username,
          icon: Icons.alternate_email_rounded,
          textInputAction: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Choose a username'
              : (v.trim().contains(' ') ? 'No spaces allowed' : null),
        ),
        const SizedBox(height: 16),
        AppField(
          'Email address',
          controller: _email,
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: (v) =>
              (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _busy ? null : _sendCode,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send verification code'),
        ),
        const SizedBox(height: 12),
        Text(
          'We email you a 6-digit code to confirm your address.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _stepTwo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField('First name',
            controller: _firstName,
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next),
        const SizedBox(height: 12),
        AppField('Last name',
            controller: _lastName,
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next),
        const SizedBox(height: 16),
        Text('Verification code sent to ${_email.text.trim()}',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        OtpField(controller: _code),
        if (_debugCode != null) ...[
          const SizedBox(height: 10),
          Text(
            'Development code: $_debugCode',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 16),
        PasswordField('Password', controller: _password1),
        const SizedBox(height: 12),
        PasswordField('Confirm password', controller: _password2),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _complete,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create my account'),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final active = index == current;
        final done = index < current;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: active ? 34 : 12,
              height: 8,
              decoration: BoxDecoration(
                color: done || active
                    ? scheme.primary
                    : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            if (index == 0) const SizedBox(width: 8),
          ],
        );
      }),
    );
  }
}
