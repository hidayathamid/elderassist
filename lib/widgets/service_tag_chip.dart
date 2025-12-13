import 'package:flutter/material.dart';

const Color _defaultServiceTagColor = Color(0xFF00A8A7);
const Color _defaultServiceTagBorder = Color(0xFF1B1D29);

class ServiceTagChip extends StatelessWidget {
  const ServiceTagChip({
    super.key,
    required this.label,
    this.backgroundColor = _defaultServiceTagColor,
    this.foregroundColor = Colors.white,
    this.borderColor = _defaultServiceTagBorder,
    this.fontSize = 8.0,
    this.fontWeight = FontWeight.w600,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.minHeight = 26,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: foregroundColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
