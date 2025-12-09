import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'caregiver_sos_incoming_screen.dart';

class CaregiverSOSAlertsScreen extends StatelessWidget {
  const CaregiverSOSAlertsScreen({super.key});

  Future<List<_SosRequest>> _loadMatchingAlerts(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String caregiverId,
  ) async {
    final alerts = <_SosRequest>[];
    final firestore = FirebaseFirestore.instance;

    for (final doc in snapshot.docs) {
      final responderDoc = await firestore
          .collection('sos')
          .doc(doc.id)
          .collection('responders')
          .doc(caregiverId)
          .get();

      if (!responderDoc.exists) continue;

      final responder = responderDoc.data() ?? {};
      final responderStatus =
          (responder['status'] as String? ?? '').toUpperCase();
      if (responderStatus != 'PENDING' &&
          responderStatus != 'ACCEPTED') {
        continue;
      }

      final sosData = doc.data();
      alerts.add(_SosRequest(
        sosId: doc.id,
        userName: sosData['userName'] as String? ?? 'Client',
        status: responderStatus,
        distanceKm: responder['distanceKm'] as num?,
      ));
    }

    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SOS Alerts')),
        body: const Center(
          child: Text('Please sign in to view SOS alerts.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SOS Alerts')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sos')
        .where('status', whereIn: [
          'FINDING',
          'ALERT_SENT',
          'RESPONDER_ASSIGNED',
        ])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load alerts: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<_SosRequest>>(
            future: _loadMatchingAlerts(snapshot.data!, user.uid),
            builder: (context, inner) {
              if (inner.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final alerts = inner.data ?? [];
              if (alerts.isEmpty) {
                return const Center(
                  child: Text('No pending SOS requests for you.'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CaregiverSosIncomingScreen(
                              sosId: alert.sosId,
                            ),
                          ),
                        );
                      },
                      title: Text(
                        alert.userName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Distance: ${alert.distanceKm?.toStringAsFixed(1) ?? 'N/A'} km | Status: ${alert.status}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SosRequest {
  _SosRequest({
    required this.sosId,
    required this.userName,
    required this.status,
    this.distanceKm,
  });

  final String sosId;
  final String userName;
  final String status;
  final num? distanceKm;
}
