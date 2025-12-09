import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/chat_service.dart';
import '../../../services/location_service.dart';
import 'package:emergencies_disability_assistance_app/screens/caregiver/chat/caregiver_chat_screen.dart';

class CaregiverJobDetailsScreen extends StatefulWidget {
  const CaregiverJobDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<CaregiverJobDetailsScreen> createState() =>
      _CaregiverJobDetailsScreenState();
}

class _CaregiverJobDetailsScreenState extends State<CaregiverJobDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _job;
  final TextEditingController _notesController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _fetchJob();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _fetchJob() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in to view the assignment.';
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(user.uid)
          .collection('assignedBookings')
          .doc(widget.bookingId)
          .get();

      if (!doc.exists) {
        setState(() {
          _error = 'This booking was not found.';
          _isLoading = false;
        });
        return;
      }

      final data = doc.data()!;
      _notesController.text = (data['notes'] as String?) ?? '';
      setState(() {
        _job = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<bool> _updateStatus(String status, {bool includeNotes = false}) async {
    if (_job == null || _isUpdating) return false;
    setState(() => _isUpdating = true);

    final userId = (_job!['userId'] as String?) ?? '';
    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (caregiverId == null) {
      setState(() {
        _error = 'You must be signed in to update the job.';
        _isUpdating = false;
      });
      return false;
    }

    final batch = FirebaseFirestore.instance.batch();
    final bookingRef =
        FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId);
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bookings')
        .doc(widget.bookingId);
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId)
        .collection('assignedBookings')
        .doc(widget.bookingId);

    final normalizedStatus = status.toUpperCase();
    final updates = {'status': normalizedStatus};
    if (includeNotes) {
      updates['notes'] = _notesController.text;
    }

    batch.update(bookingRef, updates);
    batch.update(userRef, updates);
    batch.update(caregiverRef, updates);

    try {
      await batch.commit();
      if (!mounted) return false;
      setState(() {
        _job!.addAll(updates);
        _isUpdating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job status updated to $normalizedStatus')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
      return false;
    }
  }

  Future<void> _startJob() async {
    final success = await _updateStatus('ONGOING');
    if (!success) return;
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.isNotEmpty) {
      LocationService.instance.startLiveLocationUpdates(caregiverId);
    }
  }

  Future<void> _completeJob() async {
    final success = await _updateStatus('COMPLETED', includeNotes: true);
    if (success) {
      LocationService.instance.stopLiveLocationUpdates();
    }
  }

  Future<void> _openChat() async {
    if (_job == null) return;
    final userId = (_job!['userId'] as String?) ?? '';
    if (userId.isEmpty) return;

    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (caregiverId == null || caregiverId.isEmpty) return;

    final chatId = await ChatService().createOrGetChat(userId, caregiverId);
    if (chatId.isEmpty) return;

    final personName = (_job!['personName'] as String?) ?? 'Client';
    final scheduledDate = (_job!['scheduledDate'] as String?) ?? '';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverChatScreen(
          chatId: chatId,
          otherUserId: userId,
          contactName: personName,
          lastSeen: scheduledDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job Details')),
        body: Center(child: Text(_error!)),
      );
    }

    final job = _job!;
    final status = (job['status'] as String?)?.toUpperCase() ?? 'PENDING';
    final personName = (job['personName'] as String?) ?? 'Client';
    final scheduledDate = (job['scheduledDate'] as String?) ?? '';
    final startTime = (job['startTime'] as String?) ?? '';
    final endTime = (job['endTime'] as String?) ?? '';
    final service = (job['service'] as String?) ?? 'Home care';
    final price = (job['price'] as Object?)?.toString() ?? 'RM 0';
    final location = (job['address'] as String?) ?? '';
    final timeLabel = _formatTimeLabel(startTime, endTime);

    return Scaffold(
      appBar: AppBar(title: const Text('Job Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(personName, status, location, timeLabel),
          const SizedBox(height: 16),
          _buildMapPlaceholder(),
          const SizedBox(height: 16),
          _buildInfoCard(personName, service, scheduledDate, location, timeLabel),
          const SizedBox(height: 16),
          _buildNotesCard(),
          const SizedBox(height: 16),
          _buildPriceCard(price, status),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _actionButtons(status),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.chat),
            label: const Text('Chat with Client'),
            onPressed: _openChat,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String person, String status, String location, String timeLabel) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin, size: 28),
                const SizedBox(width: 12),
                Text(person,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 4),
            Text(location),
            const SizedBox(height: 4),
            Text(timeLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: Text('Map placeholder')),
      ),
    );
  }

  Widget _buildInfoCard(String personName, String service, String scheduledDate,
      String location, String timeLabel) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        title: const Text('Person'),
        subtitle: Text('$personName - $service'),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(scheduledDate),
            Text(timeLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add any job notes or completion summary',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceCard(String price, String status) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        title: const Text('Price'),
        subtitle: Text(price),
        trailing: Text(status),
      ),
    );
  }

  List<Widget> _actionButtons(String status) {
    if (_isUpdating) {
      return [
        const SizedBox(
          width: 64,
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        )
      ];
    }

    final normalized = status.toUpperCase();
    if (normalized == 'ONGOING') {
      return [
        _ActionButton(label: 'Complete Job', onPressed: _completeJob),
      ];
    }

    if (normalized == 'COMPLETED' || normalized == 'CANCELLED') {
      return [
        const Text('Job already finalized', style: TextStyle(fontWeight: FontWeight.bold)),
      ];
    }

    return [
      _ActionButton(label: 'Start Job', onPressed: _startJob),
    ];
  }

  String _formatTimeLabel(String start, String end) {
    final trimmedStart = start.trim();
    final trimmedEnd = end.trim();
    if (trimmedStart.isEmpty && trimmedEnd.isEmpty) {
      return '';
    }
    if (trimmedStart.isEmpty) return trimmedEnd;
    if (trimmedEnd.isEmpty) return trimmedStart;
    return '$trimmedStart - $trimmedEnd';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(160, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label),
    );
  }
}
