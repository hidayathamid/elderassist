import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

import '../activity/activity_tracking_helpers.dart';

const Color _sosBorder = Color(0xFFEBEDF0);
const Color _sosAccent = Color(0xFF00A8A7);
const Color _sosTitleColor = Color(0xFF1B1D29);

class SosTrackingScreen extends StatefulWidget {
  const SosTrackingScreen({
    super.key,
    required this.sosId,
    required this.caregiverId,
  });

  final String sosId;
  final String caregiverId;

  @override
  State<SosTrackingScreen> createState() => _SosTrackingScreenState();
}

class _SosTrackingScreenState extends State<SosTrackingScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentTarget;

  void _moveCamera(LatLng target) {
    if (_mapController == null) return;
    if (_currentTarget != null &&
        _currentTarget!.latitude == target.latitude &&
        _currentTarget!.longitude == target.longitude) {
      return;
    }
    _currentTarget = target;
    _mapController!.animateCamera(CameraUpdate.newLatLng(target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildProfileStyleAppBar(
        title: 'Track responder',
        onBack: () => Navigator.of(context).pop(),
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sos')
            .doc(widget.sosId)
            .snapshots(),
        builder: (context, sosSnapshot) {
          if (!sosSnapshot.hasData || !sosSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final sosData = sosSnapshot.data!.data()!;
          final userLat = (sosData['userLat'] as num?)?.toDouble();
          final userLng = (sosData['userLng'] as num?)?.toDouble();
          final status =
              (sosData['status'] as String?)?.toUpperCase() ?? 'SEARCHING';
          final timeline = buildTimelineEvents(sosData);
          final position =
              (userLat != null && userLng != null) ? LatLng(userLat, userLng) : null;
          return Stack(
            children: [
              if (position != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('caregivers')
                      .doc(widget.caregiverId)
                      .collection('liveLocation')
                      .doc('current')
                      .snapshots(),
                  builder: (context, locationSnapshot) {
                    final markers = <Marker>{};
                    markers.add(
                      Marker(
                        markerId: const MarkerId('user'),
                        position: position,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                        infoWindow: const InfoWindow(title: 'You'),
                      ),
                    );
                    LatLng? caregiverPosition;
                    if (locationSnapshot.hasData &&
                        locationSnapshot.data!.exists) {
                      final locationData = locationSnapshot.data!.data()!;
                      final caregiverLat =
                          (locationData['lat'] as num?)?.toDouble();
                      final caregiverLng =
                          (locationData['lng'] as num?)?.toDouble();
                      if (caregiverLat != null && caregiverLng != null) {
                        caregiverPosition = LatLng(caregiverLat, caregiverLng);
                        markers.add(
                          Marker(
                            markerId: const MarkerId('caregiver'),
                            position: caregiverPosition,
                            icon:
                                BitmapDescriptor.defaultMarkerWithHue(40),
                            infoWindow:
                                const InfoWindow(title: 'Responder'),
                          ),
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _moveCamera(caregiverPosition!);
                        });
                      }
                    }

                    return GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: caregiverPosition ?? position,
                        zoom: 15,
                      ),
                      markers: markers,
                      onMapCreated: (controller) => _mapController = controller,
                    );
                  },
                )
              else
                const Center(child: Text('Waiting for your location...')),
              Positioned(
                top: kScreenHorizontalPaddingValue,
                left: kScreenHorizontalPaddingValue,
                right: kScreenHorizontalPaddingValue,
                child: _buildHeaderCard(sosData),
              ),
              Positioned(
                bottom: kScreenHorizontalPaddingValue,
                left: kScreenHorizontalPaddingValue,
                right: kScreenHorizontalPaddingValue,
                child: _buildStatusCard(status, timeline),
              ),
              Positioned(
                bottom: 140,
                left: kScreenHorizontalPaddingValue,
                right: kScreenHorizontalPaddingValue,
                child: _buildCaregiverSnapshot(sosData),
              ),
              if (position != null)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _sosBorder),
                      ),
                      child: const Text(
                        'Caregivers are being directed to you.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> sosData) {
    final userName = (sosData['userName'] as String?) ?? 'You';
    final reason = (sosData['reason'] as String?) ?? 'SOS alert';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _sosTitleColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              reason,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaregiverSnapshot(Map<String, dynamic> sosData) {
    final caregiverId = (sosData['caregiverId'] as String?) ?? '';
    if (caregiverId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .snapshots(),
      builder: (context, snapshot) {
        final caregiverData = snapshot.data?.data();
        final name = (caregiverData?['name'] as String?) ?? 'Responder';
        final specialty =
            (caregiverData?['specialization'] as String?) ?? 'Home care';
        final avatar = (caregiverData?['photoUrl'] as String?) ??
            'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(avatar),
              radius: 22,
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _sosTitleColor,
              ),
            ),
            subtitle: Text(
              specialty,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(String status, List<TimelineEvent> timeline) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _sosBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current status',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _sosTitleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: status == 'RESOLVED' ? Colors.green : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (timeline.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.separated(
                itemCount: timeline.length,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (_, index) =>
                    _buildTimelineRow(timeline[index], index == timeline.length - 1),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
              ),
            )
          else
            const Text(
              'Waiting for updates...',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(TimelineEvent event, bool isLast) {
    final timeLabel = formatTimelineTime(event.timestamp);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _sosAccent,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: _sosBorder,
              ),
          ],
        ),
        const SizedBox(width: 10),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _sosTitleColor,
                ),
              ),
              if (event.description != null && event.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    event.description!,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
