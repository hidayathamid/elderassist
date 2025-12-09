import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/chat_service.dart';
import '../../../services/auth_service.dart';
import '../chat/user_chat_screen.dart';

import 'activity_booking_details_screen.dart';
import 'activity_edit_booking_screen.dart';
import 'track_caregiver_screen.dart';

enum BookingStatus { pending, ongoing, completed }

class ActivityBooking {
  const ActivityBooking({
    required this.id,
    required this.caregiverId,
    required this.personName,
    required this.personAddress,
    required this.service,
    required this.date,
    required this.time,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.paymentMethod,
    required this.servicePrice,
    required this.status,
    this.notes,
  });

  final String id;
  final String caregiverId;
  final String personName;
  final String personAddress;
  final String service;
  final String date;
  final String time;
  final String scheduledDate;
  final String startTime;
  final String endTime;
  final String paymentMethod;
  final double servicePrice;
  final BookingStatus status;
  final String? notes;
}

class ActivityBookingCard extends StatefulWidget {
  const ActivityBookingCard({super.key, required this.booking});

  final ActivityBooking booking;

  @override
  State<ActivityBookingCard> createState() => _ActivityBookingCardState();
}

class _ActivityBookingCardState extends State<ActivityBookingCard> {
  bool _isChatting = false;

  final _auth = AuthService();
  final _chatService = ChatService();

  // 🔥 FIXED REAL CHAT — USER OPENS CHAT WITH CAREGIVER
  Future<void> _startChat(BuildContext context) async {
    if (_isChatting) return;
    setState(() => _isChatting = true);


    try {
      final caregiverId = widget.booking.caregiverId;
      if (caregiverId.isEmpty) {
        _showSnackBar(context, 'Caregiver not assigned yet');
        return;
      }

      final userId = _auth.userId;

      final chatId = await _chatService.createOrGetChat(userId, caregiverId);
      final caregiverName = await _loadCaregiverName();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserChatScreen(
            chatId: chatId,
            otherUserId: caregiverId,
            otherUserName: caregiverName,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar(context, 'Unable to open chat: $e');
    } finally {
      if (mounted) setState(() => _isChatting = false);
    }
  }

  // TRACK CAREGIVER (UNCHANGED)
  Future<void> _openTrack(BuildContext context) async {
    try {
      final caregiverId = widget.booking.caregiverId;
      if (caregiverId.isEmpty) {
        _showSnackBar(context, 'Caregiver not assigned yet');
        return;
      }

      final caregiverName = await _loadCaregiverName();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackCaregiverScreen(
            caregiverId: caregiverId,
            caregiverName: caregiverName,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar(context, 'Unable to open tracker: $e');
    }
  }

  // HELPER
  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityBookingDetailsScreen(bookingId: widget.booking.id),
      ),
    );
  }

  void _editBooking(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityEditBookingScreen(booking: widget.booking),
      ),
    );
  }

  Future<String> _loadCaregiverName() async {
    final doc = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(widget.booking.caregiverId)
        .get();
    return doc.data()?['name'] as String? ?? 'Caregiver';
  }

  List<_ActionButton> _actionButtons(BuildContext context) {
    final chatButton = _ActionButton(
      label: 'Chat',
      onPressed: _isChatting ? null : () => _startChat(context),
      icon: Icons.chat_bubble_outline,
    );

    switch (widget.booking.status) {
      case BookingStatus.pending:
        return [
          _ActionButton(
            label: 'View Details',
            onPressed: () => _openDetails(context),
            icon: Icons.remove_red_eye_outlined,
          ),
          _ActionButton(
            label: 'Edit',
            onPressed: () => _editBooking(context),
            icon: Icons.edit_outlined,
          ),
          chatButton,
        ];
      case BookingStatus.ongoing:
        return [
          _ActionButton(
            label: 'Track',
            onPressed: () => _openTrack(context),
            icon: Icons.navigation_outlined,
            primary: true,
          ),
          chatButton,
        ];
      case BookingStatus.completed:
        return [
          _ActionButton(
            label: 'View Details',
            onPressed: () => _openDetails(context),
            icon: Icons.info_outline,
          ),
          chatButton,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('caregivers')
          .doc(widget.booking.caregiverId)
          .get(),
      builder: (context, caregiverSnapshot) {
        final caregiverData = caregiverSnapshot.data?.data() ?? {};
        final caregiverName =
            caregiverData['name'] as String? ?? 'Caregiver';
        final caregiverPhoto = caregiverData['photoUrl'] as String? ??
            'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';
        final specialization =
            caregiverData['specialization'] as String? ?? '';
        final personName = widget.booking.personName;
        final personAddress = widget.booking.personAddress.isNotEmpty
            ? widget.booking.personAddress
            : 'No address provided';

        return Container(
          clipBehavior: Clip.hardEdge,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: NetworkImage(caregiverPhoto),
                      backgroundColor: Colors.grey[200],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caregiverName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            specialization,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusChip(status: widget.booking.status),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        size: 12, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      widget.booking.date,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time,
                        size: 12, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      widget.booking.time,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Text(
                          personName.isNotEmpty
                              ? personName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              personAddress,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.booking.notes?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      widget.booking.notes!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _actionButtons(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (status) {
      BookingStatus.pending => 'Scheduled',
      BookingStatus.ongoing => 'Ongoing',
      BookingStatus.completed => 'Completed',
    };
    final color = switch (status) {
      BookingStatus.pending => Colors.grey.shade600,
      BookingStatus.ongoing => Colors.blue.shade700,
      BookingStatus.completed => Colors.green.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    this.onPressed,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );

    final ButtonStyle style = primary
        ? ElevatedButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            minimumSize: const Size(84, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: radius),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          )
        : OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            minimumSize: const Size(84, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: radius),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          );

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: primary
          ? ElevatedButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton(onPressed: onPressed, style: style, child: child),
    );
  }
}
