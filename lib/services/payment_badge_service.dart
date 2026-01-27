import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentBadgeService {
  const PaymentBadgeService._();

  static Stream<int> userNewPaymentsCount() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream<int>.value(0);

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    return _newPaymentsCountStream(
      accountRef: userRef,
      paymentsQuery: FirebaseFirestore.instance
          .collection('payments')
          .where('userId', isEqualTo: uid),
      includeIf: (data) {
        if ((data['hidden'] as bool?) == true) return false;
        final status = (data['status'] as num?)?.toInt();
        final paymentStatus =
            (data['paymentStatus'] as String?)?.trim().toUpperCase();
        if (status == 3 || paymentStatus == 'FAILED') return false;
        return true;
      },
    );
  }

  static Stream<int> caregiverNewPaymentsCount() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream<int>.value(0);

    final caregiverRef =
        FirebaseFirestore.instance.collection('caregivers').doc(uid);
    return _newPaymentsCountStream(
      accountRef: caregiverRef,
      paymentsQuery: FirebaseFirestore.instance
          .collection('payments')
          .where('booking.caregiverId', isEqualTo: uid),
      includeIf: (data) {
        if ((data['hidden'] as bool?) == true) return false;
        final status = (data['status'] as num?)?.toInt();
        final paymentStatus =
            (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? '';
        final bookingStatus =
            (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
        if (status == 3 || paymentStatus == 'FAILED') return false;

        // Match ProfilePaymentsScreen caregiver POV: only show paid or cancelled.
        final isPaid = status == 1 || paymentStatus == 'PAID' || paymentStatus == 'SUCCESS';
        final isCancelled =
            bookingStatus.contains('CANCEL') ||
            paymentStatus == 'CANCELLED' ||
            paymentStatus == 'CANCELED' ||
            paymentStatus == 'REFUND_REQUESTED' ||
            paymentStatus == 'REFUNDED';
        return isPaid || isCancelled;
      },
    );
  }

  static Stream<int> _newPaymentsCountStream({
    required DocumentReference<Map<String, dynamic>> accountRef,
    required Query<Map<String, dynamic>> paymentsQuery,
    required bool Function(Map<String, dynamic> data) includeIf,
  }) {
    return accountRef.snapshots().asyncExpand((doc) {
      final data = doc.data();
      final lastSeen =
          (data?['lastSeenPaymentHistoryAt'] as Timestamp?) ??
          Timestamp(0, 0);

      return paymentsQuery
          .where('updatedAt', isGreaterThan: lastSeen)
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .map((snap) {
        var count = 0;
        for (final payment in snap.docs) {
          final paymentData = payment.data();
          if (!includeIf(paymentData)) continue;
          count++;
        }
        return count;
      });
    }).distinct();
  }
}
