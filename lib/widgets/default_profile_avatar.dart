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

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = photoUrl?.trim();
    final hasImage = trimmedUrl?.isNotEmpty == true;
    final displayChar = label?.trim().isNotEmpty == true
        ? label!.trim()[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor.withOpacity(0.18),
      backgroundImage: hasImage ? NetworkImage(trimmedUrl!) : null,
      child: hasImage
          ? null
          : Text(
              displayChar,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accentColor,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }
}
