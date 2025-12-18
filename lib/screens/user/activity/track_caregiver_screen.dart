import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/live_location_map.dart';
import '../../../widgets/standard_app_bar.dart';
import 'activity_tracking_helpers.dart';

const Color _cardBorder = Color(0xFFEBEDF0);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);

class TrackCaregiverScreen extends StatelessWidget {
  const TrackCaregiverScreen({
    super.key,
    required this.bookingId,
    required this.caregiverName,
  });

  final String bookingId;
  final String caregiverName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildProfileStyleAppBar(
        title: 'Track caregiver',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('bookings').doc(bookingId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Waiting for caregiver updates...'));
          }

          final booking = snapshot.data!.data()!;
          final caregiverId = (booking['caregiverId'] as String?) ?? '';
          final userId = (booking['userId'] as String?) ?? '';
          final service = normalizeString(booking['service']) ?? 'Home care';
          final personName = normalizeString(booking['personName']) ?? 'Your loved one';
          final location = normalizeString(booking['personAddress']) ??
              normalizeString(booking['addressLabel']) ??
              'Location not provided';
          final date = normalizeString(booking['date']) ?? '';
          final time = normalizeString(booking['time']) ?? '';
          final status = (normalizeString(booking['status']) ?? 'PENDING').toUpperCase();
          final timeline = buildTimelineEvents(booking);

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: DefaultProfileAvatar(
                    radius: 36,
                    photoUrl: normalizeString(booking['caregiverPhoto']) ??
                        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80',
                    label: caregiverName,
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    caregiverName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _profileDarkText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    service,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LiveLocationMap(
                    caregiverId: caregiverId,
                    userId: userId,
                    height: 220,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            personName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _profileDarkText,
                            ),
                          ),
                          _StatusChip(label: status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_month, size: 16, color: _accentGreen),
                          const SizedBox(width: 6),
                          Text(
                            date,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 16, color: _accentGreen),
                          const SizedBox(width: 6),
                          Text(
                            time,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: _accentGreen),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              location,
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Live updates',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: timeline.length,
                  itemBuilder: (_, index) =>
                      _buildTrackingRow(timeline[index], index == timeline.length - 1),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrackingRow(TimelineEvent event, bool isLast) {
    final timeLabel = formatTimelineTime(event.timestamp);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: _cardBorder,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (timeLabel.isNotEmpty)
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _profileDarkText,
                ),
              ),
              if (event.description != null && event.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    event.description!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toUpperCase();
    var color = _accentGreen;
    if (normalized == 'COMPLETED') color = Colors.green;
    if (normalized == 'CANCELLED') color = Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
