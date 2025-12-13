import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'sos_root_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

class SosCountdownScreen extends StatefulWidget {
  const SosCountdownScreen({super.key});

  @override
  State<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends State<SosCountdownScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _timer;
  int _secondsRemaining = 5;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _triggerSOS();
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  Future<void> _triggerSOS() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final position = await _getCurrentPosition();
      final sosId = await _createSOS(
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SosRootScreen(sosId: sosId)),
      );
    } catch (error, stack) {
      debugPrint("SOS ERROR TYPE: ${error.runtimeType}");
      debugPrint("SOS ERROR: $error");
      debugPrint("STACK TRACE: $stack");

      if (error is FirebaseFunctionsException) {
        debugPrint("SOS ERROR CODE: ${error.code}");
        debugPrint("SOS ERROR MESSAGE: ${error.message}");
        debugPrint("SOS ERROR DETAILS: ${error.details}");
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to trigger SOS: $error')));

      setState(() => _isProcessing = false);
    }
  }

  void _handleBack() {
    if (_isProcessing) return;
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<String> _createSOS({required double lat, required double lng}) async {
    final app = Firebase.app(); // 🔥 force default app
    final auth = FirebaseAuth.instanceFor(app: app);

    final user = auth.currentUser;
    debugPrint("🔥 AUTH USER UID: ${user?.uid}");

    if (user == null) {
      throw Exception("User not logged in");
    }

    final functions = FirebaseFunctions.instanceFor(
      app: app, // 🔥 SAME APP
      region: 'us-central1',
    );

    final callable = functions.httpsCallable('handleSOSAlert');

    final result = await callable.call({'lat': lat, 'lng': lng});

    final data = Map<String, dynamic>.from(result.data as Map);
    final sosId = data['sosId'] as String?;

    if (sosId == null || sosId.isEmpty) {
      throw Exception('SOS creation response missing id');
    }

    return sosId;
  }

  Future<Position> _getCurrentPosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission denied');
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildProfileStyleAppBar(
        title: 'Activating SOS',
        onBack: _handleBack,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: kHorizontalScreenPadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1 + _pulseController.value * 0.3;
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.error,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$_secondsRemaining',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isProcessing) ...[
              Text(
                'Cancel if this was accidental',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Cancel'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Sending SOS alert...'),
            ],
          ],
        ),
      ),
    );
  }
}
