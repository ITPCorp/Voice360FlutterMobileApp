import 'package:flutter/material.dart';
import '../tokens.dart';

/// Initials-or-image avatar with deterministic color from the name.
class V360Avatar extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double size;
  final bool showOnlineDot;
  final bool isOnline;

  const V360Avatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 40,
    this.showOnlineDot = false,
    this.isOnline = false,
  });

  static const List<List<Color>> _gradients = [
    [Color(0xFF0EA5E9), Color(0xFF0284C7)], // sky
    [Color(0xFF22C55E), Color(0xFF15803D)], // green
    [Color(0xFF7C3AED), Color(0xFF5B21B6)], // purple
    [Color(0xFFF59E0B), Color(0xFFB45309)], // amber
    [Color(0xFFEC4899), Color(0xFFBE185D)], // pink
    [Color(0xFF06B6D4), Color(0xFF0E7490)], // cyan
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // violet
    [Color(0xFFF43F5E), Color(0xFFB91C1C)], // rose
  ];

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  List<Color> get _gradient {
    final n = (name ?? '?').toLowerCase();
    int hash = 0;
    for (int i = 0; i < n.length; i++) {
      hash = (hash * 31 + n.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _gradients[hash % _gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final fontSize = size * 0.4;
    Widget core = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasImage
            ? null
            : LinearGradient(
                colors: _gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: hasImage
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(fontSize),
            )
          : _fallback(fontSize),
    );

    if (!showOnlineDot) return core;

    final dotSize = size * 0.28;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? V360Colors.success500 : V360Colors.gray400,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(double fontSize) {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
