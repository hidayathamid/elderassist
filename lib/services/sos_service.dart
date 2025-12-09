import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sos_model.dart';

class SOSService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get SOS by ID
  Future<SOSModel?> getSOS(String sosId) async {
    try {
      final snap = await _db.collection("sos").doc(sosId).get();
      if (!snap.exists) return null;

      return SOSModel.fromMap(snap.id, snap.data()!);
    } catch (_) {
      return null;
    }
  }

  // Stream SOS status for live updates
  Stream<SOSModel?> streamSOS(String sosId) {
    return _db.collection("sos").doc(sosId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return SOSModel.fromMap(snap.id, snap.data()!);
    });
  }

  // Stream responders list
  Stream<List<Map<String, dynamic>>> streamResponders(String sosId) {
    return _db
        .collection("sos")
        .doc(sosId)
        .collection("responders")
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
}
