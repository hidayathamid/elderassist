import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'sos_finding_screen.dart';
import 'sos_resolved_screen.dart';
import 'sos_tracking_screen.dart';

class SosRootScreen extends StatelessWidget {
  const SosRootScreen({super.key, required this.sosId});

  final String sosId;

  static const _findingStatuses = {
    'FINDING',
    'ALERT_SENT',
    'RESPONDER_PENDING',
    'RESPONDER_FOUND',
  };

  static const _trackingStatuses = {
    'RESPONDER_ASSIGNED',
    'EN_ROUTE',
    'ARRIVED',
    'RESPONDER_FOUND',
  };

  static const _resolvedStatuses = {
    'RESOLVED',
    'NO_RESPONDER',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Status')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('sos').doc(sosId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load SOS: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data!;
          if (!doc.exists) {
            return const Center(child: Text('SOS request not found.'));
          }

          final data = doc.data()!;
          final status = (data['status'] as String?)?.toUpperCase() ?? 'FINDING';
          final responderId = (data['responderId'] as String?) ??
              (data['assignedCaregiverId'] as String?) ??
              (data['caregiverId'] as String?);

          if (_findingStatuses.contains(status)) {
            return SosFindingScreen(sosId: sosId);
          }

          if (_trackingStatuses.contains(status) && responderId != null) {
            return SosTrackingScreen(
              sosId: sosId,
              caregiverId: responderId,
            );
          }

          if (_resolvedStatuses.contains(status)) {
            return SosResolvedScreen(sosId: sosId);
          }

          if (responderId != null) {
            return SosTrackingScreen(
              sosId: sosId,
              caregiverId: responderId,
            );
          }

          return SosFindingScreen(sosId: sosId);
        },
      ),
    );
  }
}
