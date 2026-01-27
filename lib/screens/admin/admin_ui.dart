import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../user/activity/activity_screen.dart'
    show activityAccentBlue, activityBackgroundColor, activityPrimaryTextColor;
import '../../widgets/standard_app_bar.dart';

const Color adminAccentGold = Color(0xFFF4B63D);

Widget buildAdminEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: activityAccentBlue),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: activityPrimaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}

class AdminTabScaffold extends StatelessWidget {
  const AdminTabScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: buildProfileStyleAppBar(title: title, actions: actions),
      body: body,
    );
  }
}

class AdminEntryTransition extends StatefulWidget {
  const AdminEntryTransition({
    super.key,
    required this.child,
    this.tabIndexListenable,
    required this.tabIndex,
  });

  final Widget child;
  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<AdminEntryTransition> createState() => _AdminEntryTransitionState();
}

class _AdminEntryTransitionState extends State<AdminEntryTransition>
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
        _entryController.forward(from: 0);
      } else {
        _entryController.value = 1;
      }
    });
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _entryController.forward(from: 0);
    }
    _wasActive = isActive;
  }

  @override
  void didUpdateWidget(covariant AdminEntryTransition oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(position: _entrySlide, child: widget.child),
    );
  }
}
