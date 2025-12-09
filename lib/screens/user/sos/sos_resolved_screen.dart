import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SosResolvedScreen extends StatelessWidget {
  const SosResolvedScreen({super.key, required this.sosId});

  final String sosId;

  void _backToHome(BuildContext context) {
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  String _formatTimestamp(DateTime? dateTime) {
    final target = dateTime ?? DateTime.now();
    return DateFormat('dd MMM yyyy hh:mm a').format(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Update')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('sos').doc(sosId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load SOS update: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data()!;
          final status = (data['status'] as String?)?.toUpperCase() ?? 'RESOLVED';
          final userName = data['userName'] as String? ?? 'Client';
          final responderName = data['responderName'] as String? ?? 'Responder';
          final resolvedAt = (data['resolvedAt'] as Timestamp?)?.toDate();
          final displayTime = _formatTimestamp(resolvedAt);
          final icon = status == 'NO_RESPONDER'
              ? Icons.warning_amber
              : Icons.check_circle;
          final iconColor =
              status == 'NO_RESPONDER' ? Colors.orange : Colors.green;
          final statusMessage = status == 'NO_RESPONDER'
              ? 'No caregivers were available to respond. Please try again later or contact emergency services.'
              : 'Your SOS request has been resolved. A caregiver has assisted you.';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: iconColor),
                const SizedBox(height: 20),
                Text(
                  status == 'NO_RESPONDER' ? 'SOS Unserved' : 'SOS Resolved',
                  style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Client: $userName',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Responder: $responderName',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Time: $displayTime',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Status: $status',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      statusMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => _backToHome(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
