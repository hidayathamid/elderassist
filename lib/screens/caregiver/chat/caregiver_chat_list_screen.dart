import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../chat/chat_list_screen.dart';

class CaregiverChatListScreen extends StatefulWidget {
  const CaregiverChatListScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<CaregiverChatListScreen> createState() => _CaregiverChatListScreenState();
}

class _CaregiverChatListScreenState extends State<CaregiverChatListScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) == widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasActive) {
        _playEntryAnimation();
      } else {
        _entryController.value = 1;
      }
    });
  }

  void _playEntryAnimation() {
    _entryController.forward(from: 0);
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _playEntryAnimation();
    }
    _wasActive = isActive;
  }

  @override
  void didUpdateWidget(covariant CaregiverChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) == widget.tabIndex;
    }
  }

  @override
  void dispose() {
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedBody(Widget child) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(position: _entrySlide, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final chatService = ChatService();
    final caregiverId = auth.userId;

    return _buildAnimatedBody(
      ChatListScreen(
        title: 'Messages',
        stream: chatService.streamCaregiverChats(caregiverId),
        userId: caregiverId,
        hideCallAction: false,
      ),
    );
  }
}
