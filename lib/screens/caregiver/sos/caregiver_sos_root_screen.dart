import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'caregiver_sos_alerts_screen.dart';
import '../../user/activity/track_caregiver_screen.dart';

class CaregiverSosRootScreen extends StatelessWidget {
  const CaregiverSosRootScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  String _normalizeStatus(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
  }

  bool _isActiveTrackingStatus(String value) {
    final status = _normalizeStatus(value);
    return status == 'EMERGENCY_ALERT' ||
        status == 'ASSIGNED' ||
        status == 'SCHEDULED' ||
        status == 'ONGOING' ||
        status == 'IN_PROGRESS' ||
        status == 'HANDLE_CLIENT';
  }

  Widget _buildTabContent(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return CaregiverSOSAlertsScreen(
        tabIndexListenable: tabIndexListenable,
        tabIndex: tabIndex,
      );
    }

    // Important: do not listen to the full caregiver document here. That doc
    // changes frequently (e.g. live location), which would rebuild the SOS tab
    // and make TrackCaregiverScreen look like it's "refreshing". We only care
    // about `activeSosId`, so map+distinct it.
    final activeSosIdStream = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['activeSosId'] as String?)?.trim() ?? '')
        .distinct();

    final offerStream = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(uid)
        .collection('sosOffers')
        .where('status', isEqualTo: 'OFFERED')
        .limit(1)
        .snapshots();

    return StreamBuilder<String>(
      stream: activeSosIdStream,
      builder: (context, activeSnapshot) {
        final activeSosId = (activeSnapshot.data ?? '').trim();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: offerStream,
          builder: (context, offerSnapshot) {
            String offerSosId = '';
            final docs = offerSnapshot.data?.docs ?? const [];
            if (docs.isNotEmpty) {
              final offerData = docs.first.data();
              final fromField = (offerData['sosId'] as String?)?.trim() ?? '';
              offerSosId = fromField.isNotEmpty ? fromField : docs.first.id;
            }

            final sosIdToShow =
                activeSosId.isNotEmpty ? activeSosId : offerSosId;
            if (sosIdToShow.isEmpty) {
              return CaregiverSOSAlertsScreen(
                tabIndexListenable: tabIndexListenable,
                tabIndex: tabIndex,
              );
            }

            final isActive = activeSosId.isNotEmpty;
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('sos')
                  .doc(sosIdToShow)
                  .snapshots(),
              builder: (context, sosSnapshot) {
                if (!sosSnapshot.hasData) {
                  return CaregiverSOSAlertsScreen(
                    tabIndexListenable: tabIndexListenable,
                    tabIndex: tabIndex,
                    activeSosId: isActive ? activeSosId : null,
                  );
                }
                if (!sosSnapshot.data!.exists) {
                  if (isActive) {
                    FirebaseFirestore.instance
                        .collection('caregivers')
                        .doc(uid)
                        .set(
                      {'activeSosId': FieldValue.delete()},
                      SetOptions(merge: true),
                    );
                  }
                  return CaregiverSOSAlertsScreen(
                    tabIndexListenable: tabIndexListenable,
                    tabIndex: tabIndex,
                  );
                }

                final sosData =
                    sosSnapshot.data!.data() ?? const <String, dynamic>{};
                final linkedBookingId =
                    (sosData['bookingId'] as String?)?.trim() ?? '';

                if (linkedBookingId.isNotEmpty) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('bookings')
                        .doc(linkedBookingId)
                        .snapshots(),
                    builder: (context, bookingSnapshot) {
                      final bookingData = bookingSnapshot.data?.data();
                      final bookingStatus =
                          (bookingData?['status'] as String?) ?? '';
                      if (bookingSnapshot.hasData &&
                          bookingSnapshot.data!.exists &&
                          !_isActiveTrackingStatus(bookingStatus)) {
                        if (isActive) {
                          FirebaseFirestore.instance
                              .collection('caregivers')
                              .doc(uid)
                              .set(
                            {'activeSosId': FieldValue.delete()},
                            SetOptions(merge: true),
                          );
                        }
                        return CaregiverSOSAlertsScreen(
                          tabIndexListenable: tabIndexListenable,
                          tabIndex: tabIndex,
                        );
                      }

                      // Show assigned layout in the SOS tab. Tracking is available
                      // via the action button inside the alerts screen.
                      if (isActive) {
                        return CaregiverSOSAlertsScreen(
                          tabIndexListenable: tabIndexListenable,
                          tabIndex: tabIndex,
                          activeSosId: activeSosId,
                        );
                      }
                      return TrackCaregiverScreen(
                        bookingId: '',
                        caregiverName: 'Caregiver',
                        sosId: sosIdToShow,
                        showStatusUpdateButton: true,
                        showActionFrontSheet: true,
                        showBackButton: false,
                        appBarTitle: 'Emergency Assistance',
                        suppressSosLinkedBookingNavigation: false,
                        forceSosSheetStyle: true,
                      );
                    },
                  );
                }

                if (isActive) {
                  return CaregiverSOSAlertsScreen(
                    tabIndexListenable: tabIndexListenable,
                    tabIndex: tabIndex,
                    activeSosId: activeSosId,
                  );
                }
                return TrackCaregiverScreen(
                  bookingId: '',
                  caregiverName: 'Caregiver',
                  sosId: sosIdToShow,
                  showStatusUpdateButton: true,
                  showActionFrontSheet: true,
                  showBackButton: false,
                  appBarTitle: 'Emergency Assistance',
                  suppressSosLinkedBookingNavigation: false,
                  forceSosSheetStyle: true,
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenable = tabIndexListenable;
    if (listenable == null) {
      return _buildTabContent(context);
    }

    // SOS flow widgets can trigger navigation internally (e.g. when an offer
    // becomes a booking). Gate rendering behind the active tab to avoid
    // unexpected route changes while the caregiver is on other tabs.
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, currentTabIndex, _) {
        if (currentTabIndex != tabIndex) {
          return const SizedBox.shrink();
        }
        return _buildTabContent(context);
      },
    );
  }
}
