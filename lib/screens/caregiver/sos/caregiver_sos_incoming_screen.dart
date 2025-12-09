import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/location_service.dart';
import 'caregiver_sos_active_screen.dart';

class CaregiverSosIncomingScreen extends StatefulWidget {
  const CaregiverSosIncomingScreen({super.key, required this.sosId});

  final String sosId;

  @override
  State<CaregiverSosIncomingScreen> createState() =>
      _CaregiverSosIncomingScreenState();
}

class _CaregiverSosIncomingScreenState
    extends State<CaregiverSosIncomingScreen> {
  Map<String, dynamic>? _sosData;
  Map<String, dynamic>? _responderData;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadAlert();
  }

  Future<void> _loadAlert() async {
    final sosRef =
        FirebaseFirestore.instance.collection('sos').doc(widget.sosId);
    final doc = await sosRef.get();
    final user = FirebaseAuth.instance.currentUser;
    Map<String, dynamic>? responder;
    if (user != null) {
      final responderSnap =
          await sosRef.collection('responders').doc(user.uid).get();
      responder = responderSnap.exists ? responderSnap.data() : null;
    }

    setState(() {
      _sosData = doc.data();
      _responderData = responder;
      _loading = false;
    });
  }

  Future<void> _handleAccept() async {
    if (_processing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _processing = true);

    try {
      final sosRef =
          FirebaseFirestore.instance.collection('sos').doc(widget.sosId);
      final responderRef =
          sosRef.collection('responders').doc(user.uid);
    final responderName = _responderData?['caregiverName'] ??
        user.displayName ??
        'Caregiver';

    final batch = FirebaseFirestore.instance.batch();
    batch.update(responderRef, {'status': 'ACCEPTED'});
    batch.update(sosRef, {
      'status': 'RESPONDER_ASSIGNED',
      'responderId': user.uid,
      'responderName': responderName,
      'assignedAt': FieldValue.serverTimestamp(),
    });

      await batch.commit();
      LocationService.instance.startLiveLocationUpdates(user.uid);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverSOSActiveScreen(sosId: widget.sosId),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept alert: $e')),
      );
      setState(() => _processing = false);
    }
  }

  Future<void> _handleDecline() async {
    if (_processing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _processing = true);

    try {
      final sosRef =
          FirebaseFirestore.instance.collection('sos').doc(widget.sosId);
      final responderRef =
          sosRef.collection('responders').doc(user.uid);

    await responderRef.update({'status': 'DECLINED'});
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decline alert: $e')),
      );
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = _sosData?['userName'] as String? ?? 'Client';
    final distance =
        (_responderData?['distanceKm'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.6),
      body: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Emergency Alert',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$userName · $distance km away',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _sosData?['userAddress'] as String? ??
                            'Location not shared yet',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _processing ? null : () => _handleDecline(),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                              ),
                              onPressed:
                                  _processing ? null : () => _handleAccept(),
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                      if (_processing) ...[
                        const SizedBox(height: 12),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
