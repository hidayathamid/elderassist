import 'package:flutter/material.dart';

import 'activity/activity_screen.dart';
import 'booking/booking_person_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_overview_screen.dart';
import 'sos/sos_activate_screen.dart';

const Color _navBarBackground = Colors.white;
const Color _idleSosBackground = _navBarBackground;

class UserRootScreen extends StatefulWidget {
  const UserRootScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<UserRootScreen> createState() => _UserRootScreenState();
}

class _UserRootScreenState extends State<UserRootScreen> {
  late int _selectedIndex;

  static const List<Widget> _pages = [
    UserHomeScreen(),
    BookingPersonScreen(),
    SosActivateScreen(),
    ActivityScreen(),
    ProfileOverviewScreen(),
  ];

  static const Color _activeBlue = Color(0xFF00B8C6);

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void initState() {
    super.initState();
    final maxIndex = _pages.length - 1;
    final requested = widget.initialIndex;
    if (requested < 0) {
      _selectedIndex = 0;
    } else if (requested > maxIndex) {
      _selectedIndex = maxIndex;
    } else {
      _selectedIndex = requested;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _navBarBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 6,
        bottom: bottomInset > 0 ? bottomInset : 8,
      ),
      child: Row(
        children: [
          _NavBubbleItem(
            icon: Icons.home_filled,
            label: 'Home',
            index: 0,
            isActive: _selectedIndex == 0,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(0),
          ),
          _NavBubbleItem(
            icon: Icons.add_circle_outline,
            label: 'Book',
            index: 1,
            isActive: _selectedIndex == 1,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(1),
          ),
          _NavBubbleItem(
            icon: Icons.sos_rounded,
            label: 'Emergency',
            index: 2,
            isActive: _selectedIndex == 2,
            isSos: true,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(2),
          ),
          _NavBubbleItem(
            icon: Icons.receipt_long_rounded,
            label: 'Activity',
            index: 3,
            isActive: _selectedIndex == 3,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(3),
          ),
          _NavBubbleItem(
            icon: Icons.person_2_rounded,
            label: 'Account',
            index: 4,
            isActive: _selectedIndex == 4,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(4),
          ),
        ],
      ),
    );
  }
}

class _NavBubbleItem extends StatefulWidget {
  const _NavBubbleItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.isSos = false,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool isActive;
  final bool isSos;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  State<_NavBubbleItem> createState() => _NavBubbleItemState();
}

class _NavBubbleItemState extends State<_NavBubbleItem> {
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
    final Color labelColor = isActive ? widget.activeColor : inactiveColor;
    final double scale = _pressed ? 0.92 : 1.0;

    final Widget iconBubble = widget.isSos
        ? Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? Colors.red : _idleSosBackground,
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
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
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
