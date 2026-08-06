import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A 6-digit OTP input rendered as individual boxes.
class OtpField extends StatefulWidget {
  const OtpField({
    super.key,
    required this.controller,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  late final TextEditingController _digits;
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _digits = widget.controller;
    _digits.addListener(_syncFromText);
  }

  @override
  void dispose() {
    _digits.removeListener(_syncFromText);
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _syncFromText() {
    final value = _digits.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (value.length > 6) {
      _digits.value = TextEditingValue(text: value.substring(0, 6));
    }
    final target = value.length.clamp(0, 5);
    if (target < 6 && !_nodes[target].hasFocus) {
      // Only move focus when typing, not on programmatic clears.
    }
    widget.onChanged?.call(value);
    setState(() {});
  }

  void _onDigitChanged(int index, String value) {
    final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length <= 1) {
      final text = _digits.text;
      final chars = text.split('');
      if (index < chars.length) chars[index] = clean;
      _digits.value = TextEditingValue(text: chars.join());
    } else {
      // Pasting a longer value.
      final merged = _digits.text;
      _digits.value = TextEditingValue(
          text: (merged.substring(0, index) + clean).substring(0, 6));
    }
    if (clean.isNotEmpty && index < 5) {
      _nodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  String _charAt(int index) {
    final text = _digits.text.replaceAll(RegExp(r'[^0-9]'), '');
    return index < text.length ? text[index] : '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 46,
          height: 56,
          child: TextField(
            enabled: widget.enabled,
            controller: TextEditingController(text: _charAt(index)),
            focusNode: _nodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              // maxLength 1
              _SingleDigitFormatter(),
            ],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: scheme.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.primary, width: 2),
              ),
            ),
            onChanged: (v) => _onDigitChanged(index, v),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        );
      }),
    );
  }
}

class _SingleDigitFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= 1) return newValue;
    return oldValue;
  }
}

/// Password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField(this.label, {super.key, this.controller});

  final String label;
  final TextEditingController? controller;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: const [AutofillHints.password],
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
