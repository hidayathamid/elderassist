import 'package:flutter/material.dart';

const Color _profileAppBarText = Color(0xFF1B1D29);

PreferredSizeWidget buildProfileStyleAppBar({
  required String title,
  VoidCallback? onBack,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    automaticallyImplyLeading: false,
    leading: onBack == null
        ? null
        : IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileAppBarText,
              size: 20,
            ),
          ),
    actions: actions,
    flexibleSpace: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: _profileAppBarText,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
    ),
  );
}
