import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'activity_booking_card.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final Map<String, String> _lastStatuses = {};
  bool _dialogShowing = false;

  static const Color _activityAppBarText = Color(0xFF1B1D29);

  BookingStatus _statusFromString(String status) {
    switch (status.toUpperCase()) {
      case 'ONGOING':
        return BookingStatus.ongoing;
      case 'COMPLETED':
        return BookingStatus.completed;
      default:
        return BookingStatus.pending;
    }
  }

  ActivityBooking _mapFromDoc(Map<String, dynamic> data, String docId) {
    final date = (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '';
    final time = (data['time'] as String?) ?? '';
    final scheduledDate = (data['scheduledDate'] as String?) ?? date;
    final startTime = (data['startTime'] as String?) ?? '';
    final endTime = (data['endTime'] as String?) ?? '';
    final paymentMethod = (data['paymentMethod'] as String?) ?? 'Unknown';
    final servicePrice = (data['servicePrice'] as num?)?.toDouble() ?? 0.0;
    return ActivityBooking(
      id: docId,
      caregiverId: (data['caregiverId'] as String?) ?? '',
      personName: (data['personName'] as String?) ?? 'Family member',
      personAddress: (data['personAddress'] as String?) ?? '',
      service: (data['service'] as String?) ?? 'Home care',
      date: date,
      time: time,
      scheduledDate: scheduledDate,
      startTime: startTime,
      endTime: endTime,
      paymentMethod: paymentMethod,
      servicePrice: servicePrice,
      status: _statusFromString((data['status'] as String?) ?? 'PENDING'),
      notes: (data['notes'] as String?),
    );
  }

  void _maybeShowAssignmentDialog(List<_BookingSnapshot> snapshots) {
    for (final snapshot in snapshots) {
      final prev = _lastStatuses[snapshot.bookingId];
      _lastStatuses[snapshot.bookingId] = snapshot.status;
      if (prev == 'PENDING' &&
          snapshot.status == 'ASSIGNED' &&
          !_dialogShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          setState(() => _dialogShowing = true);
          final caregiverDoc = await FirebaseFirestore.instance
              .collection('caregivers')
              .doc(snapshot.caregiverId)
              .get();
          final caregiverName =
              caregiverDoc.data()?['name'] as String? ?? 'your caregiver';
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Caregiver Assigned'),
              content: Text('Your caregiver for this booking is $caregiverName.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          setState(() => _dialogShowing = false);
        });
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view activity')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: const Text(
          'Activity',
          style: TextStyle(
            color: _activityAppBarText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No bookings yet'));
          }

          final raw = docs.map((doc) {
            final data = doc.data();
            final status = (data['status'] as String?) ?? 'PENDING';
            return _BookingSnapshot(
              bookingId: doc.id,
                  booking: _mapFromDoc(data, doc.id),
                  status: status,
                  caregiverId: (data['caregiverId'] as String?) ?? '',
                );
              })
              .toList();
          _maybeShowAssignmentDialog(raw);
          final bookings = raw.map((item) => item.booking).toList();
          final upcoming = bookings.where((b) {
            return b.status == BookingStatus.pending ||
                b.status == BookingStatus.ongoing;
          }).toList();
          final history = bookings
              .where((b) => b.status == BookingStatus.completed)
              .toList();

          return DefaultTabController(
            initialIndex: 0,
            length: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.black54,
                      tabs: const [
                        Tab(text: 'Upcoming'),
                        Tab(text: 'History'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(upcoming),
                      _buildList(history),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(List<ActivityBooking> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No items'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => ActivityBookingCard(booking: list[index]),
    );
  }
}

class _BookingSnapshot {
  const _BookingSnapshot({
    required this.bookingId,
    required this.booking,
    required this.status,
    required this.caregiverId,
  });

  final String bookingId;
  final ActivityBooking booking;
  final String status;
  final String caregiverId;
}
