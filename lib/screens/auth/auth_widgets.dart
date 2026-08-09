import 'package:flutter/material.dart';

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
  final List<TextEditingController> _boxes = List.generate(
      6, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _digits = widget.controller;
    _digits.addListener(_syncFromExternal);
    _syncFromExternal();
  }

  @override
  void dispose() {
    _digits.removeListener(_syncFromExternal);
    for (final n in _nodes) {
      n.dispose();
    }
    for (final b in _boxes) {
      b.dispose();
    }
    super.dispose();
  }

  /// Reflects programmatic changes made to the shared controller from outside
  /// (autofill, resets…), keeping each box in sync.
  void _syncFromExternal() {
    final value = _digits.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (value.length > 6) {
      _digits.value = TextEditingValue(text: value.substring(0, 6));
      return;
    }
    _writeValue(value, notify: false);
  }

  /// Stores [value] (digits only) into the shared controller and the boxes.
  void _writeValue(String value, {required bool notify}) {
    if (_digits.text != value) {
      _digits.value = TextEditingValue(
          text: value, selection: TextSelection.collapsed(offset: value.length));
    }
    for (var i = 0; i < 6; i++) {
      final char = i < value.length ? value[i] : '';
      if (_boxes[i].text != char) {
        _boxes[i].value = TextEditingValue(
            text: char,
            selection: char.isEmpty
                ? const TextSelection.collapsed(offset: 0)
                : const TextSelection.collapsed(offset: 1));
      }
    }
    if (notify) widget.onChanged?.call(value);
    setState(() {});
  }

  void _onDigitChanged(int index, String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final current = _digits.text;

    if (clean.isEmpty) {
      // Deletion: drop the digit at [index] and shift the rest left.
      final chars = current.split('')..removeAt(index < current.length ? index : current.length - 1);
      final next = chars.join();
      _writeValue(next, notify: true);
      if (index > 0) {
        _nodes[(index - 1).clamp(0, 5)].requestFocus();
      } else {
        _nodes[0].requestFocus();
      }
      return;
    }

    // Pad to a fixed 6 positions so a digit lands exactly in its box.
    final chars = List<String>.generate(
        6, (i) => i < current.length ? current[i] : '');
    if (clean.length == 1) {
      chars[index] = clean;
    } else {
      // Pasting a longer value (e.g. the full 6-digit code).
      for (var i = 0; i < clean.length && index + i < 6; i++) {
        chars[index + i] = clean[i];
      }
    }
    _writeValue(chars.join(), notify: true);
    if (index < 5) {
      _nodes[(index + clean.length.clamp(1, 6 - index)).clamp(0, 5)].requestFocus();
    }
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
            controller: _boxes[index],
            focusNode: _nodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
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
