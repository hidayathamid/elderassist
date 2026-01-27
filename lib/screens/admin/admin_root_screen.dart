import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../user/activity/activity_screen.dart' show activityBackgroundColor;
import 'admin_home_screen.dart';
import 'admin_bookings_screen.dart';
import 'admin_sos_screen.dart';
import 'admin_users_screen.dart';
import 'admin_profile_screen.dart';

const Color _adminNavActiveTeal = Color(0xFF00A8A7);
const Color _adminNavBarBackground = Colors.white;
const Color _adminIdleSosBackground = _adminNavBarBackground;

class AdminRootScreen extends StatefulWidget {
  const AdminRootScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AdminRootScreen> createState() => _AdminRootScreenState();
}

class _AdminRootScreenState extends State<AdminRootScreen> {
  late int _selectedIndex;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      AdminHomeScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 0),
      AdminBookingsScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 1),
      AdminSosScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 2),
      AdminUsersScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 3),
      AdminProfileScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 4),
    ];

    final maxIndex = _pages.length - 1;
    final requested = widget.initialIndex;
    if (requested < 0) {
      _selectedIndex = 0;
    } else if (requested > maxIndex) {
      _selectedIndex = maxIndex;
    } else {
      _selectedIndex = requested;
    }
    _tabIndexNotifier.value = _selectedIndex;
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _tabIndexNotifier.value = index;
  }

  Widget _buildBottomNav({required double bottomInset}) {
    final padding = EdgeInsets.only(
      left: 6,
      right: 6,
      top: 6,
      bottom: bottomInset > 0 ? bottomInset : 8,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _adminNavBarBackground.withValues(alpha: 0.82),
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.14),
                      width: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: Row(
            children: [
              _AdminNavBubbleItem(
                icon: Icons.home_filled,
                label: 'Home',
                isActive: _selectedIndex == 0,
                activeColor: _adminNavActiveTeal,
                onTap: () => _onItemTapped(0),
              ),
              _AdminNavBubbleItem(
                icon: Icons.receipt_long,
                label: 'Bookings',
                isActive: _selectedIndex == 1,
                activeColor: _adminNavActiveTeal,
                onTap: () => _onItemTapped(1),
              ),
              _AdminNavBubbleItem(
                icon: Icons.sos_rounded,
                label: 'Emergency',
                isActive: _selectedIndex == 2,
                isSos: true,
                activeColor: _adminNavActiveTeal,
                onTap: () => _onItemTapped(2),
              ),
              _AdminNavBubbleItem(
                icon: Icons.group,
                label: 'Users',
                isActive: _selectedIndex == 3,
                activeColor: _adminNavActiveTeal,
                onTap: () => _onItemTapped(3),
              ),
              _AdminNavBubbleItem(
                icon: Icons.person,
                label: 'Profile',
                isActive: _selectedIndex == 4,
                activeColor: _adminNavActiveTeal,
                onTap: () => _onItemTapped(4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: activityBackgroundColor,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(bottomInset: bottomInset),
    );
  }
}

class _AdminNavBubbleItem extends StatefulWidget {
  const _AdminNavBubbleItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.isSos = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isSos;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  State<_AdminNavBubbleItem> createState() => _AdminNavBubbleItemState();
}

class _AdminNavBubbleItemState extends State<_AdminNavBubbleItem> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color inactiveColor = Colors.grey[600]!;
    final bool isActive = widget.isActive;
    final Color iconColor = isActive ? widget.activeColor : inactiveColor;
    final double scale = _pressed ? 0.92 : 1.0;
    final Color labelColor = isActive ? widget.activeColor : inactiveColor;

    final Widget iconBubble = widget.isSos
        ? Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? Colors.red : _adminIdleSosBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isActive ? Colors.white : labelColor,
                width: 3,
              ),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 24,
                color: widget.isActive ? Colors.white : labelColor,
              ),
            ),
          )
        : Icon(widget.icon, size: 22, color: iconColor);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 43,
            child: OverflowBox(
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedScale(
                    scale: scale,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Transform.translate(
                      offset: Offset(0, widget.isSos ? -1 : 0),
                      child: iconBubble,
                    ),
                  ),
                  SizedBox(height: widget.isSos ? 2 : 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
