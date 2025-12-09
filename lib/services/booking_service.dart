import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/booking_model.dart';

class BookingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get booking by ID
  Future<BookingModel?> getBooking(String id) async {
    try {
      final snap = await _db.collection("bookings").doc(id).get();
      if (!snap.exists) return null;

      return BookingModel.fromMap(snap.id, snap.data()!);
    } catch (_) {
      return null;
    }
  }

  // Stream a booking (updates from Cloud Functions)
  Stream<BookingModel?> streamBooking(String id) {
    return _db.collection("bookings").doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      return BookingModel.fromMap(snap.id, snap.data()!);
    });
  }

  // Get user's bookings
  Future<List<BookingModel>> getUserBookings(String userId) async {
    try {
      final snap = await _db
          .collection("bookings")
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs
          .map((d) => BookingModel.fromMap(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Good for caregiver dashboard
  Future<List<BookingModel>> getCaregiverAssigned(String caregiverId) async {
    try {
      final snap = await _db
          .collection("bookings")
          .where('caregiverId', isEqualTo: caregiverId)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs
          .map((d) => BookingModel.fromMap(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
