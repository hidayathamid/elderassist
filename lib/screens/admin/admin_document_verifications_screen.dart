import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_ui.dart';
import '../user/activity/activity_screen.dart' show activityPrimaryTextColor;

class AdminDocumentVerificationsScreen extends StatelessWidget {
  const AdminDocumentVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('documents')
        .where('status', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(160)
        .snapshots();

    return AdminTabScaffold(
      title: 'Document verifications',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return buildAdminEmptyState(
              icon: Icons.description_outlined,
              title: 'Unable to load documents',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return buildAdminEmptyState(
              icon: Icons.description_outlined,
              title: 'No pending documents',
              subtitle: 'New document uploads will appear here.',
            );
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final name = ((data['name'] as String?) ?? '').trim();
              final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
              final updatedAt = data['updatedAt'] as Timestamp?;
              final title = name.isNotEmpty ? name : 'Document';
              final subtitleParts = <String>[];
              if (caregiverId.isNotEmpty) subtitleParts.add(caregiverId);
              final time = _formatTime(updatedAt);
              if (time.isNotEmpty) subtitleParts.add(time);
              final subtitle = subtitleParts.isEmpty
                  ? 'Pending verification'
                  : subtitleParts.join(' • ');

              return _VerificationTile(
                icon: Icons.description_outlined,
                title: title,
                subtitle: subtitle,
              );
            },
          );
        },
      ),
    );
  }
}

String _formatTime(Timestamp? stamp) {
  if (stamp == null) return '';
  try {
    return DateFormat('d MMM, h:mm a').format(stamp.toDate());
  } catch (_) {
    return '';
  }
}

class _VerificationTile extends StatelessWidget {
  const _VerificationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: adminAccentGold.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: adminAccentGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: activityPrimaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
        ],
      ),
    );
  }
}
