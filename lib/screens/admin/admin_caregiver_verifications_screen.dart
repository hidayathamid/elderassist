import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';
import '../user/activity/activity_screen.dart' show activityPrimaryTextColor;

class AdminCaregiverVerificationsScreen extends StatelessWidget {
  const AdminCaregiverVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('documents')
        .where('status', isEqualTo: false)
        .snapshots();

    return AdminTabScaffold(
      title: 'Caregiver verifications',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return buildAdminEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Unable to load verifications',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return buildAdminEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No pending verifications',
              subtitle: 'Caregivers will appear once documents require review.',
            );
          }

          final countsByCaregiver = <String, int>{};
          for (final doc in docs) {
            final caregiverId = (doc.data()['caregiverId'] as String?)?.trim() ?? '';
            if (caregiverId.isEmpty) continue;
            countsByCaregiver[caregiverId] = (countsByCaregiver[caregiverId] ?? 0) + 1;
          }
          final caregiverIds = countsByCaregiver.keys.toList()..sort();

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: caregiverIds.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final caregiverId = caregiverIds[index];
              final count = countsByCaregiver[caregiverId] ?? 0;
              return _VerificationTile(
                icon: Icons.volunteer_activism_outlined,
                title: caregiverId,
                subtitle: '$count document(s) pending',
              );
            },
          );
        },
      ),
    );
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
