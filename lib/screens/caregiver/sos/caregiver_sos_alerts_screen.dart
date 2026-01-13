import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../widgets/standard_app_bar.dart';
import 'caregiver_sos_incoming_screen.dart';

const Color _headingColor = Color(0xFF1B1D29);
const Color _subTextColor = Color(0xFF4C4F65);
const Color _pageBackground = Colors.white;
const Color _sosAccent = Colors.red;
const double _contentMaxWidth = 520;

class CaregiverSOSAlertsScreen extends StatefulWidget {
  const CaregiverSOSAlertsScreen({super.key});

  @override
  State<CaregiverSOSAlertsScreen> createState() => _CaregiverSOSAlertsScreenState();

}

class _CaregiverSOSAlertsScreenState extends State<CaregiverSOSAlertsScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerCountSub;
  StreamSubscription<User?>? _authSub;
  String? _lastHandledSosId;
  Object? _lastOfferError;
  int _lastOfferCount = 0;
  bool _isShowingIncoming = false;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      _startOfferListener();
    });
    _startOfferListener();
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    _offerCountSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void _startOfferListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _offerSub?.cancel();
    _offerCountSub?.cancel();
    _lastHandledSosId = null;
    _lastOfferError = null;
    final offerQuery = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(uid)
        .collection('sosOffers')
        .where('status', isEqualTo: 'OFFERED');

    _offerSub = offerQuery.snapshots().listen((snapshot) {
      if (!mounted) return;
      if (snapshot.docs.isEmpty) return;
      final doc = snapshot.docs.first;
      final sosId = (doc.data()['sosId'] as String?)?.trim().isNotEmpty == true
          ? (doc.data()['sosId'] as String).trim()
          : doc.id;
      if (sosId.isEmpty) return;
      if (_lastHandledSosId == sosId) return;
      _lastHandledSosId = sosId;
      if (_isShowingIncoming) return;
      _isShowingIncoming = true;
      Navigator.of(context, rootNavigator: true)
          .push(
            MaterialPageRoute(
              builder: (_) => CaregiverSosIncomingScreen(sosId: sosId),
            ),
          )
          .whenComplete(() {
            if (!mounted) return;
            _isShowingIncoming = false;
          });
    }, onDone: () {
      if (!mounted) return;
      setState(() => _lastOfferCount = 0);
    }, onError: (error) {
      debugPrint('CaregiverSOSAlertsScreen offer listener error: $error');
      if (!mounted) return;
      setState(() => _lastOfferError = error);
    });

    _offerCountSub = offerQuery.snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() => _lastOfferCount = snapshot.docs.length);
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _lastOfferError = error);
          },
        );
  }

  Widget _buildHeroButton() {
    const circleSize = 240.0;
    const innerSize = circleSize * 0.56;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            color: _sosAccent.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: _sosAccent.withValues(alpha: 0.12),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
        ),
        Container(
          width: innerSize,
          height: innerSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.power_settings_new_rounded,
              color: _sosAccent,
              size: 52,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: buildProfileStyleAppBar(title: 'Emergency'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeroButton(),
                  const SizedBox(height: 18),
                  const Text(
                    'Emergency Alerts',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _headingColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When a nearby client needs help, a pop-up alert will appear here. Keep this app open to respond quickly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _subTextColor,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    authUid.isEmpty
                        ? 'Sign in as caregiver to receive SOS offers.'
                        : (_lastOfferError != null
                            ? 'Unable to listen for offers. Please check Firestore rules/connection.'
                            : 'Listening for offers...'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _lastOfferError != null
                          ? Colors.red.shade700
                          : Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  if (authUid.isNotEmpty && _lastOfferCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Pending offers: $_lastOfferCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withValues(alpha: 0.65),
                        ),
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
