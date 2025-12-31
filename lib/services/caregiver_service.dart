import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/caregiver_model.dart';

class CaregiverService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get all caregivers (once)
  Future<List<CaregiverModel>> getAllCaregivers() async {
    try {
      final snap = await _db.collection("caregivers").get();
      return snap.docs
          .map((d) => CaregiverModel.fromMap(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Get available caregivers
  Future<List<CaregiverModel>> getAvailableCaregivers() async {
    try {
      final snap = await _db
          .collection("caregivers")
          .where("availability", isEqualTo: true)
          .get();

      return snap.docs
          .map((d) => CaregiverModel.fromMap(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Stream caregivers (live updates)
  Stream<List<CaregiverModel>> streamAvailableCaregivers() {
    return _db
        .collection("caregivers")
        .where("availability", isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CaregiverModel.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<CaregiverModel>> streamCaregivers() {
    return _db.collection("caregivers").snapshots().map(
          (snap) => snap.docs
              .map((d) => CaregiverModel.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  // Get caregiver by ID
  Future<CaregiverModel?> getCaregiver(String id) async {
    try {
      final snap = await _db.collection("caregivers").doc(id).get();
      if (!snap.exists) return null;

      return CaregiverModel.fromMap(snap.id, snap.data()!);
    } catch (_) {
      return null;
    }
  }

  // Update caregiver availability
  Future<bool> updateAvailability(String id, bool status) async {
    try {
      await _db.collection("caregivers").doc(id).update({
        "availability": status,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
