import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/user/sos/sos_activate_screen.dart';
import '../screens/user/sos/sos_tracking_screen.dart';

const Color _bannerTextColor = Color(0xFF1B1D29);
const Color _bannerBorderColor = Color(0xFFD7DCE3);

final BoxShadow _bannerShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.10),
  blurRadius: 20,
  offset: const Offset(0, 10),
);

class ActiveSosBanner extends StatelessWidget {
  const ActiveSosBanner({super.key, required this.sosId});

  final String sosId;

  @override
  Widget build(BuildContext context) {
    final trimmed = sosId.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('sos').doc(trimmed).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status = (data?['status'] as String?)?.toUpperCase().trim() ?? '';
        if (status.isEmpty ||
            status == 'RESOLVED' ||
            status == 'CANCELLED' ||
            status == 'TIMEOUT' ||
            status == 'NO_MATCH' ||
            status == 'NO_RESPONDER') {
          return const SizedBox.shrink();
        }

        final caregiverId = (data?['caregiverId'] as String?)?.trim() ?? '';
        final bool assigned =
            status == 'RESPONDER_ASSIGNED' && caregiverId.isNotEmpty;

        final title = assigned ? 'Responder assigned' : 'Emergency Calling';
        final subtitle =
            assigned ? 'Tap to track your responder.' : 'Tap to open SOS status.';

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (assigned) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SosTrackingScreen(
                    sosId: trimmed,
                    caregiverId: caregiverId,
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SosActivateScreen()),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _bannerBorderColor),
              boxShadow: [_bannerShadow],
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.sos_rounded,
                    color: Colors.red,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _bannerTextColor,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _bannerBorderColor),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

