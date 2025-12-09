import 'package:flutter/material.dart';

import 'activity/activity_screen.dart';
import 'booking/booking_person_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_overview_screen.dart';
import 'sos/sos_activate_screen.dart';

class UserRootScreen extends StatefulWidget {
  const UserRootScreen({
    Key? key,
    this.initialIndex = 0,
  }) : super(key: key);

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
        color: Colors.white,
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
            label: 'SOS',
            index: 2,
            isActive: _selectedIndex == 2,
            isSos: true,
            activeColor: const Color(0xFFE53935),
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

class _NavBubbleItemState extends State<_NavBubbleItem>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  void _initPulse() {
    if (!widget.isSos) return;
    _pulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation ??= Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
  }

  void _disposePulse() {
    _pulseController?.dispose();
    _pulseController = null;
    _pulseAnimation = null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.isSos) {
      _initPulse();
    }
  }

  @override
  void didUpdateWidget(covariant _NavBubbleItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSos && _pulseController == null) {
      _initPulse();
    } else if (!widget.isSos && _pulseController != null) {
      _disposePulse();
    }
  }

  @override
  void dispose() {
    _disposePulse();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color inactiveColor = Colors.grey[600]!;
    final bool isActive = widget.isActive;
    final Color iconColor = isActive ? widget.activeColor : inactiveColor;
    final double scale = _pressed ? 0.92 : 1.0;

    final Animation<double> glowAnimation = widget.isSos
        ? (_pulseAnimation ?? const AlwaysStoppedAnimation(1.0))
        : const AlwaysStoppedAnimation(1.0);

    final Widget iconBubble = widget.isSos
        ? AnimatedBuilder(
            animation: glowAnimation,
            builder: (context, child) {
              final glow = glowAnimation.value;
              return Transform.scale(
                scale: glow,
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: widget.activeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.activeColor.withOpacity(0.25 * glow),
                        blurRadius: 10 + (glow - 1) * 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
            child: Icon(widget.icon, size: 24, color: Colors.white),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: iconBubble,
              ),
              if (!widget.isSos) ...[
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11,
                    color: isActive ? widget.activeColor : inactiveColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
