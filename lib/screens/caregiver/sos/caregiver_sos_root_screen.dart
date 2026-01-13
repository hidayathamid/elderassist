import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'caregiver_sos_active_screen.dart';
import 'caregiver_sos_alerts_screen.dart';

class CaregiverSosRootScreen extends StatelessWidget {
  const CaregiverSosRootScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const CaregiverSOSAlertsScreen();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('caregivers').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final activeSosId = (data?['activeSosId'] as String?)?.trim() ?? '';
        if (activeSosId.isNotEmpty) {
          return CaregiverSOSActiveScreen(
            sosId: activeSosId,
            tabIndexListenable: tabIndexListenable,
            tabIndex: tabIndex,
          );
        }
        return const CaregiverSOSAlertsScreen();
      },
    );
  }
}

