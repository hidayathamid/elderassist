import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class TrackCaregiverScreen extends StatefulWidget {
  const TrackCaregiverScreen({
    super.key,
    required this.caregiverId,
    required this.caregiverName,
  });

  final String caregiverId;
  final String caregiverName;

  @override
  State<TrackCaregiverScreen> createState() => _TrackCaregiverScreenState();
}

class _TrackCaregiverScreenState extends State<TrackCaregiverScreen> {
  GoogleMapController? _mapController;
  Marker? _caregiverMarker;
  static const _initialPosition = CameraPosition(target: LatLng(0, 0), zoom: 16);

  void _updateMarker(double lat, double lng) {
    final marker = Marker(
      markerId: const MarkerId('caregiver'),
      position: LatLng(lat, lng),
      infoWindow: InfoWindow(title: widget.caregiverName),
    );

    setState(() {
      _caregiverMarker = marker;
    });

    _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track Caregiver')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .doc(widget.caregiverId)
            .collection('liveLocation')
            .doc('current')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Waiting for caregiver location...'));
          }

          final doc = snapshot.data!;
          final lat = (doc['lat'] as num?)?.toDouble();
          final lng = (doc['lng'] as num?)?.toDouble();
          final updatedAt = doc['updatedAt'] as Timestamp?;

          if (lat == null || lng == null) {
            return const Center(child: Text('Waiting for caregiver location...'));
          }

          _updateMarker(lat, lng);

          final updatedStr = updatedAt != null
              ? DateFormat('hh:mm:ss a').format(updatedAt.toDate())
              : 'n/a';

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: _initialPosition,
                markers: _caregiverMarker != null ? {_caregiverMarker!} : {},
                onMapCreated: (controller) => _mapController = controller,
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Caregiver: ${widget.caregiverName}'),
                        Text('Last updated: $updatedStr'),
                      ],
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
}
