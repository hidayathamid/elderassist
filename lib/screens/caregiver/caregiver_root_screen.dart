import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import 'chat/caregiver_chat_list_screen.dart';
import 'home/caregiver_home_screen.dart';
import 'jobs/caregiver_jobs_screen.dart';
import 'profile/caregiver_profile_screen.dart';
import 'sos/caregiver_sos_alerts_screen.dart';

const Color _caregiverNavActiveBlue = Color(0xFF00A8A7);
const Color _caregiverChatBadgeColor = Color(0xFF00A8A7);
const Color _caregiverNavShadowColor = Color(0x14000000);
const Color _caregiverNavBarBackground = Colors.white;
const Color _caregiverIdleSosBackground = _caregiverNavBarBackground;

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
          color: _caregiverNavBarBackground,
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
            label: 'Emergency',
            index: 2,
            isActive: _selectedIndex == 2,
            isSos: true,
            activeColor: _caregiverNavActiveBlue,
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

class _CaregiverNavBubbleItemState extends State<_CaregiverNavBubbleItem> {
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
              color: widget.isActive ? Colors.red : _caregiverIdleSosBackground,
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
                      child: applyBadge(iconBubble),
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
