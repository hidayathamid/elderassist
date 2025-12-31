import 'package:flutter/material.dart';

const Color _defaultAvatarAccent = Color(0xFF00A8A7);
const Color _defaultAvatarFill = Color.fromARGB(255, 181, 212, 212);

class DefaultProfileAvatar extends StatelessWidget {
  const DefaultProfileAvatar({
    super.key,
    this.photoUrl,
    this.label,
    this.radius = 24,
    this.backgroundColor = _defaultAvatarFill,
    this.accentColor = _defaultAvatarAccent,
  });

  final String? photoUrl;
  final String? label;
  final double radius;
  final Color backgroundColor;
  final Color accentColor;

  Widget _fallbackText(String displayChar) {
    return Text(
      displayChar,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: accentColor,
        fontSize: radius * 0.8,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = photoUrl?.trim();
    final hasImage = trimmedUrl?.isNotEmpty == true;
    final displayChar = label?.trim().isNotEmpty == true
        ? label!.trim()[0].toUpperCase()
        : '?';
    final double size = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor.withValues(alpha: 0.18),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _fallbackText(displayChar)),
              if (hasImage)
                Image.network(
                  trimmedUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
