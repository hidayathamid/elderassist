import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';
import 'caregiver_sos_resolved_screen.dart';

const Color _sosBackgroundColor = Color(0xFFF7F8FA);
const Color _sosPrimaryTextColor = Color(0xFF1B1D29);
const Color _sosAccentTeal = Color(0xFF00A8A7);
const Color _sosCardBorderColor = Color(0xFFD1D6DE);
const BorderRadius _sosCardRadius = BorderRadius.all(Radius.circular(18));
const double _sosButtonHeight = 44;
const double _sosContentMaxWidth = 520;

int _alphaFromOpacity(double opacity) {
  final value = (opacity * 255).round();
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value;
}

final BoxShadow _sosCardShadow = BoxShadow(
  color: Colors.black.withAlpha(_alphaFromOpacity(0.12)),
  blurRadius: 16,
  offset: const Offset(0, 8),
);

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _sosCardRadius,
        border: Border.all(color: _sosCardBorderColor),
        boxShadow: [_sosCardShadow],
      ),
      child: child,
    );
  }
}

class CaregiverSOSActiveScreen extends StatefulWidget {
  const CaregiverSOSActiveScreen({
    super.key,
    required this.sosId,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final String sosId;
  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<CaregiverSOSActiveScreen> createState() =>
      _CaregiverSOSActiveScreenState();
}

class _CaregiverSOSActiveScreenState extends State<CaregiverSOSActiveScreen>
    with TickerProviderStateMixin {
  bool _isProcessing = false;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;
  bool _wasActive = false;

  Future<void> _markArrived() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .update({
            'status': 'ARRIVED',
            'arrivedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as arrived')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _finishAssistance() async {
    if (_isProcessing) return;
    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (caregiverId == null) return;
    setState(() => _isProcessing = true);

    try {
      final sosSnap = await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .get();
      final sosData = sosSnap.data();
      final userId =
          (sosData?['userId'] as String?)?.trim() ??
          (sosData?['ownerUserId'] as String?)?.trim() ??
          '';
      await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .update({
            'status': 'RESOLVED',
            'resolvedAt': FieldValue.serverTimestamp(),
          });
      await FirebaseFirestore.instance.collection('caregivers').doc(caregiverId).set(
        {
          'activeSosId': FieldValue.delete(),
          'activeSosUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).set(
          {
            'activeSosId': FieldValue.delete(),
            'activeSosUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      LocationService.instance.stopLiveLocationUpdates();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverSosResolvedScreen(sosId: widget.sosId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to finish: $e')));
    }
  }

  @override
  void initState() {
    super.initState();

    final entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryController = entryController;
    _entryFade = CurvedAnimation(
      parent: entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: entryController, curve: Curves.easeOutCubic),
        );

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasActive) {
        _entryController?.forward(from: 0);
      } else {
        _entryController?.value = 1;
      }
    });
  }

  @override
  void didUpdateWidget(covariant CaregiverSOSActiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _entryController?.forward(from: 0);
    }
    _wasActive = isActive;
  }

  @override
  void dispose() {
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
    final entrySlide =
        _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);

    return FadeTransition(
      opacity: entryFade,
      child: SlideTransition(
        position: entrySlide,
        child: Scaffold(
          backgroundColor: _sosBackgroundColor,
          appBar: AppBar(
            title: const Text(
              'Responding',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _sosPrimaryTextColor,
                letterSpacing: -0.2,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: _sosBackgroundColor,
            surfaceTintColor: _sosBackgroundColor,
            foregroundColor: _sosPrimaryTextColor,
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _sosContentMaxWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const _SummaryCard(),
                    const SizedBox(height: 16),
                    const _SectionHeader(
                      title: 'SOS assistance',
                      infoMessage:
                          'Live location updates are running while you navigate to the client.',
                    ),
                    const SizedBox(height: 10),
                    const _InfoCard(),
                    const SizedBox(height: 12),
                    _ActionCard(
                      primaryColor: theme.colorScheme.primary,
                      dangerColor: theme.colorScheme.error,
                      isProcessing: _isProcessing,
                      onMarkArrived: _markArrived,
                      onFinishAssistance: _finishAssistance,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    return _PremiumCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _sosAccentTeal.withAlpha(_alphaFromOpacity(0.10)),
              shape: BoxShape.circle,
              border: Border.all(
                color: _sosAccentTeal.withAlpha(_alphaFromOpacity(0.22)),
              ),
            ),
            child: const Icon(
              Icons.sos_rounded,
              size: 20,
              color: _sosAccentTeal,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS response active',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _sosPrimaryTextColor,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Keep the app open while navigating. Update the status when you arrive, and finish assistance when it’s safe.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.infoMessage});

  final String title;
  final String infoMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _sosPrimaryTextColor,
              letterSpacing: -0.1,
            ),
          ),
        ),
        _SectionInfoIcon(message: infoMessage),
      ],
    );
  }
}

class _SectionInfoIcon extends StatefulWidget {
  const _SectionInfoIcon({required this.message});

  final String message;

  @override
  State<_SectionInfoIcon> createState() => _SectionInfoIconState();
}

class _SectionInfoIconState extends State<_SectionInfoIcon> {
  bool _showHint = false;
  Timer? _hintTimer;

  void _triggerHint() {
    _hintTimer?.cancel();
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _triggerHint,
          onLongPress: _triggerHint,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(_alphaFromOpacity(0.05)),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.10)),
              ),
            ),
            child: const Icon(
              Icons.info_outline,
              size: 16,
              color: _sosAccentTeal,
            ),
          ),
        ),
        if (_showHint)
          Positioned(
            right: -170,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return _PremiumCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _sosAccentTeal.withAlpha(_alphaFromOpacity(0.10)),
              shape: BoxShape.circle,
              border: Border.all(
                color: _sosAccentTeal.withAlpha(_alphaFromOpacity(0.22)),
              ),
            ),
            child: const Icon(
              Icons.navigation_outlined,
              size: 18,
              color: _sosAccentTeal,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Updating location to client.\nFollow directions and keep the app open.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: _sosPrimaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.primaryColor,
    required this.dangerColor,
    required this.isProcessing,
    required this.onMarkArrived,
    required this.onFinishAssistance,
  });

  final Color primaryColor;
  final Color dangerColor;
  final bool isProcessing;
  final VoidCallback onMarkArrived;
  final VoidCallback onFinishAssistance;

  @override
  Widget build(BuildContext context) {
    final disabled = isProcessing;
    final label = disabled ? 'Processing...' : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _sosCardRadius,
        border: Border.all(color: _sosCardBorderColor),
        boxShadow: [_sosCardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Actions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _sosPrimaryTextColor,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: disabled ? null : onMarkArrived,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(_sosButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(label ?? 'Mark Arrived'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: disabled ? null : onFinishAssistance,
            style: FilledButton.styleFrom(
              backgroundColor: dangerColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(_sosButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: Text(label ?? 'Finish Assistance'),
          ),
        ],
      ),
    );
  }
}
