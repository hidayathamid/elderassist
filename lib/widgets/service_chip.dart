import 'package:flutter/material.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _selectedServiceColor = Color(0xFF00A8A7);

class ServiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ServiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected ? _selectedServiceColor : Colors.white;
    final foreground = selected ? Colors.white : _profileDarkText;
    final borderColor =
        selected ? const Color.fromARGB(32, 0, 0, 0) : const Color.fromARGB(32, 0, 0, 0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
