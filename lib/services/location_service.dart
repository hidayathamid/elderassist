import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();
  Timer? _timer;

  Future<bool> requestPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      return requested == LocationPermission.whileInUse ||
          requested == LocationPermission.always;
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  /// Update caregiver location every 5 seconds
  void startLiveLocationUpdates(String caregiverId) {
    stopLiveLocationUpdates(); // ensure no duplicate timer

    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final hasPermission = await requestPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition();

      // SAVE DIRECTLY INTO caregiver document (backend expects this)
      await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .update({
            'lat': position.latitude,
            'lng': position.longitude,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    });
  }

  void stopLiveLocationUpdates() {
    _timer?.cancel();
    _timer = null;
  }
}
