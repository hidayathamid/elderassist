import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/standard_app_bar.dart';
import '../../user/activity/activity_screen.dart';

const List<String> _alertStatuses = [
  'SEARCHING',
  'ALERT_SENT',
  'FINDING',
  'RESPONDER_ASSIGNED',
];

const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(18));
const int _statusBgAlpha = 31; // ~0.12
const int _statusBorderAlpha = 77; // ~0.3

class CaregiverSOSAlertsScreen extends StatelessWidget {
  const CaregiverSOSAlertsScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _alertStream() {
    return FirebaseFirestore.instance
        .collection('sos')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _updateResponderStatus({
    required String sosId,
    required String caregiverId,
    String? responderStatus,
    String? documentStatus,
  }) async {
    final sosRef = FirebaseFirestore.instance.collection('sos').doc(sosId);
    final responderRef = sosRef.collection('responders').doc(caregiverId);
    final batch = FirebaseFirestore.instance.batch();
    if (responderStatus != null) {
      batch.set(
        responderRef,
        {'status': responderStatus, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    if (documentStatus != null) {
      batch.update(sosRef, {
        'status': documentStatus,
        'responderId': caregiverId,
      });
    }
    await batch.commit();
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final moment = timestamp.toDate();
    return DateFormat('MMM d, h:mm a').format(moment);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(title: 'SOS Alerts'),
        backgroundColor: Colors.white,
        body: const Center(child: Text('Please sign in to view SOS alerts.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildProfileStyleAppBar(title: 'SOS Alerts'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _alertStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load alerts: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs
              .where((doc) => _alertStatuses.contains(
                    ((doc.data()['status'] as String?)?.toUpperCase() ?? ''),
                  ))
              .toList();
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No active SOS alerts at the moment.',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final status = (data['status'] as String?)?.toUpperCase() ?? 'SEARCHING';
              final reason = (data['reason'] as String?) ?? 'General support';
              final name = (data['userName'] as String?) ?? 'Client';
              final address = (data['address'] as String?) ?? 'Location not shared';
              final distance = (data['responderDistanceKm'] as num?) ??
                  (data['distanceKm'] as num?) ??
                  (data['distance'] as num?);
              final timestamp = _formatTimestamp(data['createdAt'] as Timestamp?);

              return _SosCard(
                sosId: doc.id,
                caregiverId: user.uid,
                name: name,
                address: address,
                reason: reason,
                status: status,
                distanceKm: distance,
                timestamp: timestamp,
                onAction: (action) async {
                  try {
                    if (action == _SosAction.acknowledge) {
                      await _updateResponderStatus(
                        sosId: doc.id,
                        caregiverId: user.uid,
                        responderStatus: 'ACKNOWLEDGED',
                        documentStatus: 'RESPONDER_ASSIGNED',
                      );
                    } else if (action == _SosAction.ontheWay) {
                      await _updateResponderStatus(
                        sosId: doc.id,
                        caregiverId: user.uid,
                        responderStatus: 'ON_THE_WAY',
                        documentStatus: 'RESPONDER_ASSIGNED',
                      );
                    } else if (action == _SosAction.resolve) {
                      await _updateResponderStatus(
                        sosId: doc.id,
                        caregiverId: user.uid,
                        responderStatus: 'COMPLETED',
                        documentStatus: 'RESOLVED',
                      );
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Alert updated (${action.label})')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Unable to update alert: $e')),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

enum _SosAction { acknowledge, ontheWay, resolve }

extension on _SosAction {
  String get label {
    return switch (this) {
      _SosAction.acknowledge => 'Acknowledge',
      _SosAction.ontheWay => 'On the way',
      _SosAction.resolve => 'Mark resolved',
    };
  }
}

class _SosCard extends StatelessWidget {
  const _SosCard({
    required this.sosId,
    required this.caregiverId,
    required this.name,
    required this.address,
    required this.reason,
    required this.status,
    required this.distanceKm,
    required this.timestamp,
    required this.onAction,
  });

  final String sosId;
  final String caregiverId;
  final String name;
  final String address;
  final String reason;
  final String status;
  final num? distanceKm;
  final String timestamp;
  final Future<void> Function(_SosAction action) onAction;

  Color get _statusColor {
    final normalized = status.toLowerCase();
    if (normalized.contains('alert') || normalized.contains('search')) {
      return Colors.orange;
    }
    if (normalized.contains('assigned')) {
      return activityAccentBlue;
    }
    return Colors.green;
  }

  String get _distanceText {
    if (distanceKm == null) return 'Distance N/A';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: _cardRadius,
          border: Border.all(color: Colors.grey.shade300),
        ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: activityAccentBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: activityPrimaryTextColor,
                    ),
                  ),
                ),
                Text(
                  timestamp,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withAlpha(_statusBgAlpha),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _statusColor.withAlpha(_statusBorderAlpha),
                    ),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: _statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _distanceText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              address,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAction(_SosAction.acknowledge),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Acknowledge',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAction(_SosAction.ontheWay),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: activityAccentBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'On the way',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: activityAccentBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => onAction(_SosAction.resolve),
                    child: const Text(
                      'Resolve',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
