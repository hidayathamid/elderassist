import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

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
  LatLng? _lastTarget;

  void _moveCamera(LatLng target) {
    if (_mapController == null) return;
    if (_lastTarget != null &&
        _lastTarget!.latitude == target.latitude &&
        _lastTarget!.longitude == target.longitude) {
      return;
    }
    _lastTarget = target;
    _mapController!.animateCamera(CameraUpdate.newLatLng(target));
  }

  String _friendlyStatus(String status) {
    switch (status.toUpperCase()) {
      case 'FINDING':
        return 'Searching for caregivers';
      case 'ALERT_SENT':
      case 'RESPONDER_PENDING':
        return 'Alert sent to caregivers';
      case 'RESPONDER_ASSIGNED':
      case 'RESPONDER_FOUND':
        return 'Responder assigned';
      case 'EN_ROUTE':
        return 'Responder en route';
      case 'ARRIVED':
        return 'Responder arrived';
      case 'RESOLVED':
        return 'Assistance completed';
      case 'NO_RESPONDER':
        return 'No responders available';
      default:
        return status;
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    return DateFormat('hh:mm:ss a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildProfileStyleAppBar(
        title: 'Emergency Assistance',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sos')
            .doc(widget.sosId)
            .snapshots(),
        builder: (context, sosSnapshot) {
          if (sosSnapshot.hasError) {
            return Center(
              child: Text('Unable to load SOS: ${sosSnapshot.error}'),
            );
          }

          if (!sosSnapshot.hasData || !sosSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final sosData = sosSnapshot.data!.data()!;
          final userLat = (sosData['userLat'] as num?)?.toDouble();
          final userLng = (sosData['userLng'] as num?)?.toDouble();
          final userPosition = (userLat != null && userLng != null)
              ? LatLng(userLat, userLng)
              : null;
          final status =
              (sosData['status'] as String?)?.toUpperCase() ?? 'FINDING';
          final statusLabel = _friendlyStatus(status);

          if (userPosition == null) {
            return const Center(child: Text('Waiting for your location...'));
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('caregivers')
                .doc(widget.caregiverId)
                .collection('liveLocation')
                .doc('current')
                .snapshots(),
            builder: (context, locationSnapshot) {
              if (locationSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Unable to load caregiver location: ${locationSnapshot.error}',
                  ),
                );
              }

              final locationData = locationSnapshot.data?.data();
              final caregiverLat = (locationData?['lat'] as num?)?.toDouble();
              final caregiverLng = (locationData?['lng'] as num?)?.toDouble();
              final caregiverPosition =
                  (caregiverLat != null && caregiverLng != null)
                  ? LatLng(caregiverLat, caregiverLng)
                  : null;
              final updatedAt = (locationData?['updatedAt'] as Timestamp?)
                  ?.toDate();
              final lastUpdated = updatedAt != null
                  ? _formatTimestamp(updatedAt)
                  : 'Updating...';

              final markers = <Marker>{};
              markers.add(
                Marker(
                  markerId: const MarkerId('user'),
                  position: userPosition,
                  icon: BitmapDescriptor.defaultMarkerWithHue(200),
                  infoWindow: const InfoWindow(title: 'You'),
                ),
              );

              if (caregiverPosition != null) {
                markers.add(
                  Marker(
                    markerId: const MarkerId('caregiver'),
                    position: caregiverPosition,
                    icon: BitmapDescriptor.defaultMarkerWithHue(40),
                    infoWindow: const InfoWindow(title: 'Caregiver'),
                  ),
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _moveCamera(caregiverPosition);
                });
              }

              final cameraPosition = caregiverPosition ?? userPosition;

              return Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: cameraPosition,
                      zoom: 15,
                    ),
                    markers: markers,
                    onMapCreated: (controller) => _mapController = controller,
                  ),
                  Positioned(
                    bottom: 20,
                    left: kScreenHorizontalPaddingValue,
                    right: kScreenHorizontalPaddingValue,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emergency Status',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              statusLabel,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Last update: $lastUpdated',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
