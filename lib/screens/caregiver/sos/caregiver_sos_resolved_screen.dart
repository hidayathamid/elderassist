import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CaregiverSosResolvedScreen extends StatelessWidget {
  const CaregiverSosResolvedScreen({super.key, required this.sosId});

  final String sosId;

  void _backToDashboard(BuildContext context) {
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    return timestamp.toDate().toLocal().toString().replaceFirst(RegExp(r'\.\d+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Resolved')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('sos').doc(sosId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load update: ${snapshot.error}'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data()!;
          final userName = data['userName'] as String? ?? 'Client';
          final responderName = data['responderName'] as String? ?? 'Responder';
          final status = (data['status'] as String?)?.toUpperCase() ?? 'RESOLVED';
          final resolvedAt = data['resolvedAt'] as Timestamp?;
          final displayTime = _formatTimestamp(resolvedAt ?? Timestamp.now());
          final icon = status == 'NO_RESPONDER'
              ? Icons.warning_amber
              : Icons.check_circle;
          final iconColor = status == 'NO_RESPONDER' ? Colors.orange : Colors.green;
          final title = status == 'NO_RESPONDER'
              ? 'SOS Ended (No Responder)'
              : 'SOS Resolved';
          final message = status == 'NO_RESPONDER'
              ? 'No responders were available to assist. Please try again later.'
              : 'Emergency assistance complete. Please ensure the client is safe and report any notes as needed.';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: iconColor),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Client: $userName',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Responder: $responderName',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Time: $displayTime',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Status: $status',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => _backToDashboard(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Back to Dashboard'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
