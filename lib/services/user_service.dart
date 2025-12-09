import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================
  // GET USER BY ID
  // ===========================================================
  Future<UserModel?> getUserById(String uid) async {
    try {
      final doc = await _firestore.collection("users").doc(uid).get();
      if (!doc.exists) return null;

      return UserModel.fromMap(doc.data()!);
    } catch (e) {
      print("getUserById error: $e");
      return null;
    }
  }

  // ===========================================================
  // UPDATE USER PROFILE (NAME / PHONE / ADDRESS)
  // ===========================================================
  Future<bool> updateUserProfile({
    required String uid,
    String? name,
    String? phone,
    List<Map<String, dynamic>>? address,
  }) async {
    try {
      Map<String, dynamic> updates = {};

      if (name != null) updates["name"] = name;
      if (phone != null) updates["phone"] = phone;
      if (address != null) updates["address"] = address;

      await _firestore.collection("users").doc(uid).update(updates);

      return true;
    } catch (e) {
      print("updateUserProfile error: $e");
      return false;
    }
  }

  // ===========================================================
  // CHECK IF USER EXISTS
  // ===========================================================
  Future<bool> userExists(String uid) async {
    try {
      final doc = await _firestore.collection("users").doc(uid).get();
      return doc.exists;
    } catch (e) {
      print("userExists error: $e");
      return false;
    }
  }

  // ===========================================================
  // GET USER BOOKINGS (USED IN HISTORY PAGE)
  // Firestore path:
  // users/{uid}/bookings/{bookingId}
  // Generated automatically by cloud function autoAssignCaregiver
  // ===========================================================
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserBookings(String uid) {
    return _firestore
        .collection("users")
        .doc(uid)
        .collection("bookings")
        .orderBy("scheduledDate", descending: true)
        .snapshots();
  }

  // ===========================================================
  // SAVE SOS HISTORY (OPTIONAL UI USE)
  // sos/{sosId}
  // ===========================================================
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserSOSHistory(String uid) {
    return _firestore
        .collection("sos")
        .where("userId", isEqualTo: uid)
        .orderBy("requestedAt", descending: true)
        .snapshots();
  }
}
