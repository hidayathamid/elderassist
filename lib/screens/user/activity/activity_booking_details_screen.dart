import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import '../../../services/chat_service.dart';
import '../../../services/auth_service.dart';
import '../chat/user_chat_screen.dart';
import 'track_caregiver_screen.dart';

const _defaultCaregiverAvatar =
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';

class ActivityBookingDetailsScreen extends StatefulWidget {
  const ActivityBookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityBookingDetailsScreen> createState() =>
      _ActivityBookingDetailsScreenState();
}

class _ActivityBookingDetailsScreenState
    extends State<ActivityBookingDetailsScreen> {
  bool _isLoading = true;
  bool _notFound = false;
  String? _error;
  Map<String, dynamic>? _booking;
  bool _isCancelling = false;

  final AuthService _auth = AuthService();
  final ChatService _chatService = ChatService();
  String _caregiverName = 'Caregiver';
  String _caregiverPhoto = _defaultCaregiverAvatar;

  @override
  void initState() {
    super.initState();
    _fetchBooking();
  }

  Future<void> _fetchBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in to view booking details.';
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();

      if (!doc.exists) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
        return;
      }

      final data = doc.data();
      setState(() {
        _booking = data;
        _isLoading = false;
      });
      final caregiverId = (data?['caregiverId'] as String?) ?? '';
      if (caregiverId.isNotEmpty) {
        await _loadCaregiverInfo(caregiverId);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking() async {
    if (_booking == null || _isCancelling) return;

    final currentStatus = (_booking!['status'] as String?)?.toUpperCase() ?? '';
    if (currentStatus == 'CANCELLED') return;

    setState(() => _isCancelling = true);

    final firestore = FirebaseFirestore.instance;
    final bookingRef = firestore.collection('bookings').doc(widget.bookingId);

    try {
      await bookingRef.update({'status': 'CANCELLED'});
      setState(() {
        _booking!['status'] = 'CANCELLED';
        _isCancelling = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancellation failed: $e')));
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _loadCaregiverInfo(String caregiverId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .get();
      final data = doc.data();
      if (data == null) return;
      final name = data['name'] as String?;
      final photo = data['photoUrl'] as String?;
      if (!mounted) return;
      setState(() {
        if (name != null && name.isNotEmpty) {
          _caregiverName = name;
        }
        if (photo != null && photo.isNotEmpty) {
          _caregiverPhoto = photo;
        }
      });
    } catch (_) {}
  }

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      if (parts.length == 3) {
        final dt = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return DateFormat('dd MMM yyyy').format(dt);
      }
    } catch (_) {}
    return raw;
  }

  String _formatTime(String raw) {
    try {
      final parsed = DateFormat('HH:mm').parseLoose(raw);
      return DateFormat('hh:mm a').format(parsed);
    } catch (_) {}
    return raw;
  }

  Future<void> _openChat() async {
    if (_booking == null) return;

    final caregiverId = (_booking!['caregiverId'] as String?) ?? '';
    if (caregiverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver not assigned yet')),
      );
      return;
    }

    final userId = _auth.userId;

    // Create or retrieve chatId
    final chatId = await _chatService.createOrGetChat(userId, caregiverId);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserChatScreen(
          chatId: chatId,
          otherUserId: caregiverId,
          otherUserName: _caregiverName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking Details')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_notFound || _booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking Details')),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final caregiverName = _caregiverName;
    final caregiverPhoto = _caregiverPhoto;
    final service = (_booking!['service'] as String?) ?? 'Home care';
    final scheduled = (_booking!['scheduledDate'] as String?) ?? '';
    final startTime = (_booking!['startTime'] as String?) ?? '';
    final endTime = (_booking!['endTime'] as String?) ?? '';
    final servicePriceValue = (_booking!['servicePrice'] as num?)?.toDouble() ?? 0.0;
    final price = 'RM ${servicePriceValue.toStringAsFixed(2)}';
    final paymentMethod = (_booking!['paymentMethod'] as String?) ?? 'Unknown';
    final status = (_booking!['status'] as String?) ?? 'PENDING';
    final caregiverId = (_booking!['caregiverId'] as String?) ?? '';
    final notes = (_booking!['notes'] as String?) ?? '';
    final personName = (_booking!['personName'] as String?) ?? 'Family member';
    final personAddress =
        (_booking!['personAddress'] as String?) ?? 'Address not provided';

    final isCancelled = status.toUpperCase() == 'CANCELLED';

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(caregiverPhoto),
                  ),
                  title: Text(
                    caregiverName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(service),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusChip(label: status),
                      Text(price, style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(_formatDate(scheduled)),
              subtitle: Text(
                '${_formatTime(startTime)} - ${_formatTime(endTime)}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: DefaultProfileAvatar(
                radius: 20,
                label: personName,
              ),
              title: Text(
                personName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                personAddress,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('Payment Method'),
              subtitle: Text(paymentMethod),
            ),
          ),
          const SizedBox(height: 12),
          if (notes.isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('Notes'),
                subtitle: Text(notes),
              ),
            ),
          const SizedBox(height: 12),

          // TRACK CAREGIVER BUTTON
          if (status.toUpperCase() == 'ONGOING' && caregiverId.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.location_on),
              label: const Text('Track Caregiver'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrackCaregiverScreen(
                      caregiverId: caregiverId,
                      caregiverName: caregiverName,
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 30),

          // CHAT BUTTON (FULLY FIXED)
          ElevatedButton.icon(
            icon: const Icon(Icons.chat),
            label: const Text('Chat with caregiver'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: caregiverId.isEmpty ? null : _openChat,
          ),

          const SizedBox(height: 12),

          // CANCEL BOOKING BUTTON
          OutlinedButton(
            onPressed: isCancelled || _isCancelling ? null : _cancelBooking,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isCancelling
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isCancelled ? 'Already cancelled' : 'Cancel Booking'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = label.toUpperCase();
    Color color;
    if (normalized == 'ONGOING') {
      color = Colors.blue;
    } else if (normalized == 'COMPLETED') {
      color = Colors.green;
    } else if (normalized == 'CANCELLED') {
      color = Colors.red;
    } else {
      color = Colors.orange;
    }

    return Chip(
      label: Text(normalized),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: theme.textTheme.bodySmall?.copyWith(color: color),
    );
  }
}
