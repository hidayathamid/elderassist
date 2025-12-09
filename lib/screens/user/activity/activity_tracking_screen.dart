import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({
    super.key,
    required this.caregiverId,
    required this.caregiverName,
    this.caregiverPhotoUrl,
  });

  final String caregiverId;
  final String caregiverName;
  final String? caregiverPhotoUrl;

  @override
  State<ActivityTrackingScreen> createState() => _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static const LatLng _userLocation = LatLng(3.1390, 101.6869);
  LatLng? _caregiverLocation;
  late CameraPosition _initialCamera;
  GoogleMapController? _controller;
  Marker? _caregiverMarker;
  String _updatedAtLabel = 'n/a';

  @override
  void initState() {
    super.initState();
    _initialCamera = const CameraPosition(target: _userLocation, zoom: 15);
  }

  void _updateMarker(LatLng position, {String? updatedLabel}) {
    final current = _caregiverLocation;
    if (current != null &&
        current.latitude == position.latitude &&
        current.longitude == position.longitude &&
        (updatedLabel == null || updatedLabel == _updatedAtLabel)) {
      return;
    }

    final marker = Marker(
      markerId: const MarkerId('caregiver'),
      position: position,
      infoWindow: InfoWindow(title: widget.caregiverName),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );

    setState(() {
      _caregiverLocation = position;
      _caregiverMarker = marker;
      if (updatedLabel != null) {
        _updatedAtLabel = updatedLabel;
      }
    });

    _controller?.animateCamera(CameraUpdate.newLatLng(position));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .doc(widget.caregiverId)
            .collection('liveLocation')
            .doc('current')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load location'));
          }

          final doc = snapshot.data;
          if (doc != null && doc.exists) {
            final data = doc.data();
            final lat = (data?['lat'] as num?)?.toDouble();
            final lng = (data?['lng'] as num?)?.toDouble();
            final updatedAt = data?['updatedAt'] as Timestamp?;
            if (lat != null && lng != null) {
              final updatedStr = updatedAt != null
                  ? DateFormat('hh:mm:ss a').format(updatedAt.toDate())
                  : 'n/a';
              _updateMarker(LatLng(lat, lng), updatedLabel: updatedStr);
            }
          }

          final markers = <Marker>{
            Marker(
              markerId: const MarkerId('user'),
              position: _userLocation,
              infoWindow: const InfoWindow(title: 'You'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
            ),
          };
          if (_caregiverMarker != null) markers.add(_caregiverMarker!);

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: _caregiverLocation != null
                    ? CameraPosition(target: _caregiverLocation!, zoom: 15)
                    : _initialCamera,
                markers: markers,
                onMapCreated: (controller) {
                  _controller ??= controller;
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(
                            widget.caregiverPhotoUrl ??
                                'https://images.unsplash.com/photo-1544723795-3fb6469f5b39?auto=format&fit=crop&w=200&q=80',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.caregiverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('Last updated: $_updatedAtLabel'),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Chat'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('View Booking'),
                        ),
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
