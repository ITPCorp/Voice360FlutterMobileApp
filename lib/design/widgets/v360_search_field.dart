import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens.dart';

class V360SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  const V360SearchField({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onClear,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(V360Radius.lg),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        inputFormatters: [LengthLimitingTextInputFormatter(80)],
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          hintText: hintText,
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          suffixIcon: (controller?.text.isNotEmpty == true && onClear != null)
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
                  onPressed: onClear,
                )
              : null,
        ),
      ),
    );
  }
}
