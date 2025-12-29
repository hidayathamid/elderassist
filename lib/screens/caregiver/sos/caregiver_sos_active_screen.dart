import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';
import 'caregiver_sos_resolved_screen.dart';

class CaregiverSOSActiveScreen extends StatefulWidget {
  const CaregiverSOSActiveScreen({super.key, required this.sosId});

  final String sosId;

  @override
  State<CaregiverSOSActiveScreen> createState() =>
      _CaregiverSOSActiveScreenState();
}

class _CaregiverSOSActiveScreenState extends State<CaregiverSOSActiveScreen> {
  bool _isProcessing = false;

  Future<void> _markArrived() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .update({
            'status': 'ARRIVED',
            'arrivedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as arrived')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _finishAssistance() async {
    if (_isProcessing) return;
    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (caregiverId == null) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .update({
            'status': 'RESOLVED',
            'resolvedAt': FieldValue.serverTimestamp(),
          });
      LocationService.instance.stopLiveLocationUpdates();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverSosResolvedScreen(sosId: widget.sosId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to finish: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Responding")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Updating location to client...\nFollow directions to assist them.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isProcessing ? null : _markArrived,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(_isProcessing ? 'Processing...' : 'Mark Arrived'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _isProcessing ? null : _finishAssistance,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                _isProcessing ? 'Processing...' : 'Finish Assistance',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
