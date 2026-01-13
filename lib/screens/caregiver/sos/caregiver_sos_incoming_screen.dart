import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:emergencies_disability_assistance_app/services/location_service.dart';

import 'caregiver_sos_active_screen.dart';

class CaregiverSosIncomingScreen extends StatefulWidget {
  const CaregiverSosIncomingScreen({super.key, required this.sosId});

  final String sosId;

  @override
  State<CaregiverSosIncomingScreen> createState() =>
      _CaregiverSosIncomingScreenState();
}

class _CaregiverSosIncomingScreenState extends State<CaregiverSosIncomingScreen> {
  bool _processing = false;
  GoogleMapController? _mapController;
  bool _didMoveCamera = false;

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> _respond(String action) async {
    if (_processing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _processing = true);
    try {
      final callable = _functions.httpsCallable('respondSosOffer');
      await callable.call(<String, dynamic>{
        'sosId': widget.sosId,
        'action': action,
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _handleAccept() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _respond('ACCEPT');
      LocationService.instance.startLiveLocationUpdates(user.uid);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverSOSActiveScreen(sosId: widget.sosId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Unable to accept'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleReject() async {
    try {
      await _respond('REJECT');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Thank you'),
          content: const Text('Thank you for your time.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Unable to reject'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _maybeMoveCamera(LatLng target) {
    if (_mapController == null) return;
    if (_didMoveCamera) return;
    _didMoveCamera = true;
    _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: uid.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance
                .collection('caregivers')
                .doc(uid)
                .collection('sosOffers')
                .doc(widget.sosId)
                .snapshots(),
        builder: (context, snapshot) {
          if (uid.isEmpty) {
            return const Center(child: Text('Please sign in to respond.'));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load alert: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('This SOS offer is no longer available.'));
          }
          final data = snapshot.data!.data() ?? const <String, dynamic>{};
          final offerStatus =
              (data['status'] as String?)?.toUpperCase().trim() ?? 'OFFERED';
          if (offerStatus != 'OFFERED') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).maybePop();
            });
            return const Center(child: Text('This SOS offer is no longer available.'));
          }
          final personName =
              (data['selectedPersonName'] as String?)?.trim().isNotEmpty == true
                  ? (data['selectedPersonName'] as String).trim()
                  : 'Client';
          final address =
              (data['address'] as String?)?.trim().isNotEmpty == true
                  ? (data['address'] as String).trim()
                  : 'Location not shared yet';
          final userLat = (data['userLat'] as num?)?.toDouble();
          final userLng = (data['userLng'] as num?)?.toDouble();
          final userPos = (userLat != null && userLng != null)
              ? LatLng(userLat, userLng)
              : null;

          final markers = <Marker>{};
          if (userPos != null) {
            markers.add(
              Marker(
                markerId: const MarkerId('client'),
                position: userPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
              ),
            );
          }

          if (userPos != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _maybeMoveCamera(userPos);
            });
          }

          final canRespond = !_processing;

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: userPos ?? const LatLng(3.1390, 101.6869),
                  zoom: userPos == null ? 12 : 15,
                ),
                zoomControlsEnabled: false,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                markers: markers,
                onMapCreated: (controller) => _mapController = controller,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Emergency Alert',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.10),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            personName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            address,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: canRespond ? _handleReject : null,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: BorderSide(
                                      color: Colors.black.withValues(alpha: 0.12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Reject',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: canRespond ? _handleAccept : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                          if (_processing) ...[
                            const SizedBox(height: 12),
                            const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              ),
                            ),
                          ],
                        ],
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
}
