import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng _defaultMapCenter = LatLng(3.1390, 101.6869);

class LiveLocationMap extends StatefulWidget {
  const LiveLocationMap({
    super.key,
    required this.caregiverId,
    this.userId,
    this.height = 220,
  });

  final String caregiverId;
  final String? userId;
  final double height;

  @override
  State<LiveLocationMap> createState() => _LiveLocationMapState();
}

class _LiveLocationMapState extends State<LiveLocationMap> {
  GoogleMapController? _mapController;
  LatLng? _lastTarget;

  @override
  Widget build(BuildContext context) {
    if (widget.caregiverId.isEmpty) {
      return _buildMessage('Caregiver location is not available yet.');
    }
    return SizedBox(
      height: widget.height,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .doc(widget.caregiverId)
            .snapshots(),
        builder: (context, caregiverSnapshot) {
          if (caregiverSnapshot.hasError) {
            return _buildMessage('Unable to load caregiver location.');
          }
          if (!caregiverSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final caregiverPosition =
              _latLngFromData(caregiverSnapshot.data?.data());
          if (widget.userId?.isNotEmpty ?? false) {
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.userId!)
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.hasError ||
                    userSnapshot.data == null ||
                    !userSnapshot.data!.exists) {
                  if (caregiverPosition == null) {
                    return _buildMessage('Waiting for live location updates...');
                  }
                  return _buildMap(caregiverPosition, null);
                }
                final userPosition =
                    _latLngFromData(userSnapshot.data?.data());
                if (caregiverPosition == null && userPosition == null) {
                  return _buildMessage('Waiting for live location updates...');
                }
                return _buildMap(caregiverPosition, userPosition);
              },
            );
          }
          if (caregiverPosition == null) {
            return _buildMessage('Waiting for caregiver location...');
          }
          return _buildMap(caregiverPosition, null);
        },
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }

  Widget _buildMap(LatLng? caregiverPosition, LatLng? userPosition) {
    final target = _calculateTarget(caregiverPosition, userPosition);
    final markers = <Marker>{};
    if (userPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: userPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Client'),
        ),
      );
    }
    if (caregiverPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('caregiver'),
          position: caregiverPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(40),
          infoWindow: const InfoWindow(title: 'Caregiver'),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mapController != null) {
        final shouldUpdate = _lastTarget == null ||
            _lastTarget!.latitude != target.latitude ||
            _lastTarget!.longitude != target.longitude;
        if (shouldUpdate) {
          _mapController!.animateCamera(CameraUpdate.newLatLng(target));
          _lastTarget = target;
        }
      }
    });

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: target,
        zoom: _determineZoom(caregiverPosition, userPosition),
      ),
      markers: markers,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        controller.moveCamera(CameraUpdate.newLatLng(target));
        _lastTarget = target;
      },
    );
  }

  double _determineZoom(LatLng? caregiver, LatLng? user) {
    if (caregiver != null && user != null) {
      final distance = _haversineDistance(caregiver, user);
      if (distance <= 0.5) return 16;
      if (distance <= 2.0) return 14;
      if (distance <= 5.0) return 12;
      return 10;
    }
    return 15;
  }

  double _haversineDistance(LatLng a, LatLng b) {
    const double earthRadius = 6371; // km
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final inner = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(inner), sqrt(1 - inner));
    return earthRadius * c;
  }

  double _degToRad(double degrees) {
    return degrees * (pi / 180);
  }

  LatLng _calculateTarget(LatLng? caregiver, LatLng? user) {
    if (caregiver != null && user != null) {
      return LatLng(
        (caregiver.latitude + user.latitude) / 2,
        (caregiver.longitude + user.longitude) / 2,
      );
    }
    return caregiver ?? user ?? _defaultMapCenter;
  }

  LatLng? _latLngFromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat = _toDouble(data['lat']) ??
        _toDouble(data['latitude']) ??
        _toDouble(data['userLat']) ??
        _toDouble(data['deviceLat']);
    final lng = _toDouble(data['lng']) ??
        _toDouble(data['longitude']) ??
        _toDouble(data['userLng']) ??
        _toDouble(data['deviceLng']);
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
