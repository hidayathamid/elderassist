import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../widgets/safe_network_image.dart';
import '../../../widgets/standard_app_bar.dart';
import '../../user/activity/activity_booking_details_screen.dart';
import '../../user/activity/track_caregiver_screen.dart';

const Color _headingColor = Color(0xFF1B1D29);
const Color _subTextColor = Color(0xFF4C4F65);
const Color _pageBackground = Colors.white;
const Color _sosAccent = Colors.red;
const Color _accentGold = Color(0xFFF4B63D);
const Color _accentBlue = Color(0xFF00A8A7);
const double _contentMaxWidth = 520;
const double _pillButtonHeight = 34.0;

class CaregiverSOSAlertsScreen extends StatefulWidget {
  const CaregiverSOSAlertsScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
    this.activeSosId,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;
  final String? activeSosId;

  @override
  State<CaregiverSOSAlertsScreen> createState() =>
      _CaregiverSOSAlertsScreenState();
}

class _CaregiverSOSAlertsScreenState extends State<CaregiverSOSAlertsScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offerCountSub;
  StreamSubscription<User?>? _authSub;
  VoidCallback? _tabListener;
  Object? _lastOfferError;
  int _lastOfferCount = 0;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      _startOfferListenerIfActive();
    });

    if (widget.tabIndexListenable != null) {
      _tabListener = () {
        if (!mounted) return;
        _startOfferListenerIfActive();
      };
      widget.tabIndexListenable!.addListener(_tabListener!);
    }

    _startOfferListenerIfActive();
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    _offerCountSub?.cancel();
    _authSub?.cancel();
    if (_tabListener != null) {
      widget.tabIndexListenable?.removeListener(_tabListener!);
      _tabListener = null;
    }
    super.dispose();
  }

  bool get _isEmergencyTabActive {
    final listenable = widget.tabIndexListenable;
    if (listenable == null) return true;
    return listenable.value == widget.tabIndex;
  }

  void _startOfferListenerIfActive() {
    if (!_isEmergencyTabActive) {
      _offerSub?.cancel();
      _offerSub = null;
      _offerCountSub?.cancel();
      _offerCountSub = null;
      return;
    }
    _startOfferListener();
  }

  void _startOfferListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _offerSub?.cancel();
    _offerCountSub?.cancel();
    _lastOfferError = null;
    final offerQuery = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(uid)
        .collection('sosOffers')
        .where('status', isEqualTo: 'OFFERED');

    _offerSub = offerQuery.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        if (!_isEmergencyTabActive) return;
        // Do not auto-open the incoming offer UI from this screen.
        // The caregiver SOS root screen decides whether to show the incoming view.
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _lastOfferCount = 0);
      },
      onError: (error) {
        debugPrint('CaregiverSOSAlertsScreen offer listener error: $error');
        if (!mounted) return;
        setState(() => _lastOfferError = error);
      },
    );

    _offerCountSub = offerQuery.snapshots().listen(
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

  Widget _buildAssignedSos({
    required String caregiverId,
    required String sosId,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos').doc(sosId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load SOS: ${snapshot.error}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data() ?? const <String, dynamic>{};
        final status = (data['status'] as String?)?.toUpperCase().trim() ?? '';
        final bookingId = (data['bookingId'] as String?)?.trim() ?? '';
        if (status.isEmpty || bookingId.isEmpty) {
          return _buildIdleCopy(
            message: 'Listening for offers...',
            showCount: true,
          );
        }

        final resolvedCaregiverName =
            (data['caregiverName'] as String?)?.trim().isNotEmpty == true
                ? (data['caregiverName'] as String).trim()
                : 'Caregiver';
        final resolvedCaregiverId =
            (data['caregiverId'] as String?)?.trim().isNotEmpty == true
                ? (data['caregiverId'] as String).trim()
                : caregiverId;
        final personId = (data['personId'] as String?)?.trim().isNotEmpty == true
            ? (data['personId'] as String).trim()
            : null;

        final personName = (data['personName'] as String?)?.trim() ??
            (data['selectedPersonName'] as String?)?.trim() ??
            'Client';
        final personAddress = (data['personAddress'] as String?)?.trim() ??
            (data['address'] as String?)?.trim() ??
            'Address unavailable';
        final addressMetaRaw = data['addressMeta'];
        final addressMeta = (addressMetaRaw is Map)
            ? Map<String, dynamic>.from(addressMetaRaw)
            : const <String, dynamic>{};
        final clientPhotoUrl = (addressMeta['photoUrl'] as String?)?.trim() ?? '';
        final clientPhone = (addressMeta['phone']?.toString().trim().isNotEmpty == true)
            ? addressMeta['phone'].toString().trim()
            : (addressMeta['phoneNumber']?.toString().trim().isNotEmpty == true)
                ? addressMeta['phoneNumber'].toString().trim()
                : (data['personPhone']?.toString().trim().isNotEmpty == true)
                    ? data['personPhone'].toString().trim()
                    : '';

        const radius = BorderRadius.all(Radius.circular(22));
        final trackStyle = ElevatedButton.styleFrom(
          backgroundColor: _accentBlue,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: radius),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadowColor: Colors.black.withValues(alpha: 38),
        );
        final detailsStyle = OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _accentBlue.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _accentBlue.withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.verified_rounded,
                                      color: _accentBlue,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Emergency alert assigned',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _headingColor,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Go to the client location and follow the session steps.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _subTextColor,
                                height: 1.35,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            Container(
                              decoration: BoxDecoration(
                                color: _accentGold,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipOval(
                                    child: SizedBox(
                                      width: 46,
                                      height: 46,
                                      child: SafeNetworkImage(
                                        clientPhotoUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          personName,
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: _headingColor,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        const Text(
                                          'Client',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black45,
                                          ),
                                        ),
                                        if (clientPhone.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            clientPhone,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                          personAddress,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 0),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TrackCaregiverScreen(
                                            bookingId: bookingId,
                                            caregiverName: resolvedCaregiverName,
                                            caregiverId: resolvedCaregiverId,
                                            personId: personId,
                                            showStatusUpdateButton: true,
                                            showActionFrontSheet: true,
                                          ),
                                        ),
                                      );
                                    },
                                    style: trackStyle,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.navigation_outlined, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Track',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ActivityBookingDetailsScreen(
                                            bookingId: bookingId,
                                            caregiverView: true,
                                          ),
                                        ),
                                      );
                                    },
                                    style: detailsStyle,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.info_outline, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'View Details',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIdleCopy({required String message, bool showCount = false}) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Center(
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
                        : message),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _lastOfferError != null
                      ? Colors.red.shade700
                      : Colors.black.withValues(alpha: 0.55),
                ),
              ),
              if (showCount && authUid.isNotEmpty && _lastOfferCount > 0)
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final forcedActiveSosId = (widget.activeSosId ?? '').trim();
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: buildProfileStyleAppBar(title: 'Emergency Assistance'),
      body: SafeArea(
        child: authUid.isEmpty
            ? _buildIdleCopy(message: 'Listening for offers...', showCount: true)
            : (forcedActiveSosId.isNotEmpty
                ? _buildAssignedSos(
                    caregiverId: authUid,
                    sosId: forcedActiveSosId,
                  )
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('caregivers')
                        .doc(authUid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final activeSosId =
                          (snapshot.data?.data()?['activeSosId'] as String?)
                                  ?.trim() ??
                              '';
                      if (activeSosId.isNotEmpty) {
                        return _buildAssignedSos(
                          caregiverId: authUid,
                          sosId: activeSosId,
                        );
                      }
                      return _buildIdleCopy(
                        message: 'Listening for offers...',
                        showCount: true,
                      );
                    },
                  )),
      ),
    );
  }
}
