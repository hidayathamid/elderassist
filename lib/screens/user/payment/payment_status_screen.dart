import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PaymentStatusScreen extends StatefulWidget {
  final String bookingId;
  final String billCode;

  const PaymentStatusScreen({
    super.key,
    required this.bookingId,
    required this.billCode,
  });

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  bool _bookingCreated = false;
  bool _isCreatingBooking = false;

  Future<void> _ensureBooking(Map<String, dynamic> bookingData) async {
    if (_bookingCreated || _isCreatingBooking) return;
    setState(() {
      _isCreatingBooking = true;
    });

    try {
      final bookingRef =
          FirebaseFirestore.instance.collection("bookings").doc(widget.bookingId);
      final snapshot = await bookingRef.get();
      if (!snapshot.exists) {
        await bookingRef.set({
          ...bookingData,
          "status": "PAID",
        });
      } else {
        await bookingRef.update({"status": "PAID"});
      }
      if (!mounted) return;
      setState(() {
        _bookingCreated = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingBooking = false;
        });
      }
    }
  }

  Widget _buildBody(String message) {
    return Scaffold(
      body: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("payments")
          .doc(widget.billCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final status = data?["status"] ?? 0;

        if (status == 1) {
          final bookingData = data?["bookingData"] as Map<String, dynamic>?;
          if (bookingData != null) {
            _ensureBooking(bookingData);
          }
          final message = _bookingCreated
              ? "Payment Successful!"
              : "Finalizing booking...";
          return _buildBody(message);
        } else if (status == 2) {
          return _buildBody("Payment Failed");
        } else if (status == 3) {
          return _buildBody("Payment Canceled");
        }

        return _buildBody("Waiting for payment...");
      },
    );
  }
}
