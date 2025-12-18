import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import 'chat/caregiver_chat_list_screen.dart';
import 'home/caregiver_home_screen.dart';
import 'jobs/caregiver_jobs_screen.dart';
import 'profile/caregiver_profile_screen.dart';
import 'sos/caregiver_sos_alerts_screen.dart';

const Color _caregiverNavActiveBlue = Color(0xFF00B8C6);
const Color _caregiverChatBadgeColor = Color(0xFF00A8A7);
const Color _caregiverNavShadowColor = Color(0x14000000);

class CaregiverRootScreen extends StatefulWidget {
  const CaregiverRootScreen({super.key});

  @override
  State<CaregiverRootScreen> createState() => _CaregiverRootScreenState();
}

class _CaregiverRootScreenState extends State<CaregiverRootScreen> {
  int _selectedIndex = 0;
  final AuthService _auth = AuthService();
  final ChatService _chatService = ChatService();

  static const List<Widget> _pages = [
    CaregiverHomeScreen(),
    CaregiverJobsScreen(),
    CaregiverSOSAlertsScreen(),
    CaregiverChatListScreen(),
    CaregiverProfileScreen(),
  ];

  void _onTabSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final caregiverId = _auth.userId;
    final chatBadgeStream = caregiverId.isNotEmpty
        ? _chatService.streamUnreadCountForCaregiver(caregiverId)
        : Stream<int>.value(0);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: _caregiverNavShadowColor,
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
            _CaregiverNavBubbleItem(
              icon: Icons.home_filled,
              label: 'Home',
              index: 0,
              isActive: _selectedIndex == 0,
              activeColor: _caregiverNavActiveBlue,
              onTap: () => _onTabSelected(0),
            ),
            _CaregiverNavBubbleItem(
              icon: Icons.list_alt,
              label: 'Jobs',
              index: 1,
              isActive: _selectedIndex == 1,
              activeColor: _caregiverNavActiveBlue,
              onTap: () => _onTabSelected(1),
            ),
            _CaregiverNavBubbleItem(
              icon: Icons.sos_rounded,
              label: 'SOS',
              index: 2,
              isActive: _selectedIndex == 2,
              isSos: true,
              activeColor: const Color(0xFFE53935),
              onTap: () => _onTabSelected(2),
            ),
            StreamBuilder<int>(
              stream: chatBadgeStream,
              builder: (context, snapshot) {
                final badgeCount = snapshot.data ?? 0;
                return _CaregiverNavBubbleItem(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat',
                  index: 3,
                  isActive: _selectedIndex == 3,
                  activeColor: _caregiverNavActiveBlue,
                  onTap: () => _onTabSelected(3),
                  badgeCount: badgeCount,
                );
              },
            ),
            _CaregiverNavBubbleItem(
              icon: Icons.person,
              label: 'Account',
              index: 4,
              isActive: _selectedIndex == 4,
              activeColor: _caregiverNavActiveBlue,
              onTap: () => _onTabSelected(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaregiverNavBubbleItem extends StatefulWidget {
  const _CaregiverNavBubbleItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.isSos = false,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool isActive;
  final bool isSos;
  final Color activeColor;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  State<_CaregiverNavBubbleItem> createState() =>
      _CaregiverNavBubbleItemState();
}

class _CaregiverNavBubbleItemState extends State<_CaregiverNavBubbleItem>
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
  void didUpdateWidget(covariant _CaregiverNavBubbleItem oldWidget) {
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
              final glowOpacity = (0.25 * glow).clamp(0.0, 1.0);
              final glowAlpha = (glowOpacity * 255)
                  .round()
                  .clamp(0, 255)
                  .toInt();
              final glowColor = widget.activeColor.withAlpha(glowAlpha);
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
                        color: glowColor,
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
    final int badgeCount = widget.badgeCount ?? 0;
    final bool hasBadge = badgeCount > 0;
    Widget applyBadge(Widget child) {
      if (!hasBadge) return child;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -4,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _caregiverChatBadgeColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      );
    }

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
                child: applyBadge(iconBubble),
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
