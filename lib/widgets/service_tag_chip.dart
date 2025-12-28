import 'package:flutter/material.dart';

const Color _defaultServiceTagColor = Colors.white;
const Color _defaultServiceTagBorder = Color(0xFFCCCCCC);

class ServiceTagChip extends StatelessWidget {
  const ServiceTagChip({
    super.key,
    required this.label,
    this.backgroundColor = _defaultServiceTagColor,
    this.foregroundColor = const Color(0xFF1B1D29),
    this.borderColor = _defaultServiceTagBorder,
    this.fontSize = 8.5,
    this.fontWeight = FontWeight.w600,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    this.minHeight = 12,
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
        borderRadius: BorderRadius.circular(10),
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
