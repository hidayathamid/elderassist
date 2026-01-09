import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';
import 'package:emergencies_disability_assistance_app/screens/user/chat/user_chat_screen.dart';
import 'package:emergencies_disability_assistance_app/services/chat_service.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';
import 'package:emergencies_disability_assistance_app/utils/service_preferences.dart';
import '../../../widgets/live_location_map.dart';

const BorderRadius _sectionBorderRadius = BorderRadius.all(Radius.circular(18));

final Color _sectionBorderColor = Colors.grey.shade300;
final BoxShadow _sectionShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 20),
  blurRadius: 16,
  offset: const Offset(0, 6),
);

final BoxShadow _chipShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 20),
  blurRadius: 8,
  offset: const Offset(0, 4),
);

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
  String? _clientDefaultAddress;
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
          .collection('bookings')
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

      final userId = (data['userId'] as String?)?.trim() ?? '';
      if (userId.isNotEmpty) {
        unawaited(_fetchClientDefaultAddress(userId));
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? _stringOrNull(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  String? _defaultAddressText(Object? raw) {
    final direct = _stringOrNull(raw);
    if (direct != null) return direct;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final line = _stringOrNull(map['address']) ??
          _stringOrNull(map['addressLine']) ??
          _stringOrNull(map['fullAddress']) ??
          _stringOrNull(map['line1']) ??
          _stringOrNull(map['subtitle']);
      return line;
    }
    return null;
  }

  Future<void> _fetchClientDefaultAddress(String userId) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = snap.data();
      if (data == null) return;
      final address = _defaultAddressText(data['defaultAddress']);
      if (!mounted) return;
      if (address == null) return;
      setState(() => _clientDefaultAddress = address);
    } catch (_) {
      // Keep silent; fallback to booking address.
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
    final bookingRef = FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
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

    final personName = (_job!['personName'] as String?) ?? 'Client';
    final chatService = ChatService();
    final chatId = await chatService.createOrGetChat(
      userId,
      caregiverId,
      personId: (_job!['personId'] as String?) ?? '',
    );
    if (chatId.isEmpty) return;
    await chatService.setChatLabel(chatId, personName);
    await chatService.setChatPersonInfo(
      chatId,
      personId: (_job!['personId'] as String?) ?? '',
      personName: personName,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserChatScreen(
          chatId: chatId,
          otherUserId: userId,
          otherUserName: personName,
          hideCallAction: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = buildProfileStyleAppBar(
      title: 'Job Details',
      onBack: () => Navigator.of(context).pop(),
    );

    if (_isLoading) {
      return Scaffold(
        backgroundColor: activityBackgroundColor,
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: activityBackgroundColor,
        appBar: appBar,
        body: Center(child: Text(_error!)),
      );
    }

    final job = _job!;
    final status = (job['status'] as String?)?.toUpperCase() ?? 'PENDING';
    final personName = (job['personName'] as String?) ?? 'Client';
    final scheduledDate = (job['scheduledDate'] as String?) ?? '';
    final startTime = (job['startTime'] as String?) ?? '';
    final endTime = (job['endTime'] as String?) ?? '';
    final rawServiceLabel = extractServiceLabelFromFirestore(job);
    final service = rawServiceLabel.isNotEmpty ? rawServiceLabel : 'Home care';
    final price = (job['price'] as Object?)?.toString() ?? 'RM 0';
    final location =
        _clientDefaultAddress?.trim().isNotEmpty == true
            ? _clientDefaultAddress!.trim()
            : (job['address'] as String?) ?? '';
    final timeLabel = _formatTimeLabel(startTime, endTime);

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildHeader(personName, service, status, location, timeLabel),
          const SizedBox(height: 16),
          _buildLiveMapSection(job),
          const SizedBox(height: 16),
          _buildInfoCard(
            personName,
            service,
            scheduledDate,
            location,
            timeLabel,
          ),
          const SizedBox(height: 16),
          _buildNotesCard(),
          const SizedBox(height: 16),
          _buildPriceCard(price, status),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: _actionButtons(status)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Chat with Client'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: Colors.grey.shade300),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(
    String person,
    String service,
    String status,
    String location,
    String timeLabel,
  ) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_pin,
                  size: 28,
                  color: activityAccentBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: activityPrimaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        service,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                _JobStatusChip(status: status),
              ],
            ),
            const SizedBox(height: 12),
            if (location.isNotEmpty)
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (location.isNotEmpty) const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.black54),
                const SizedBox(width: 4),
                Text(
                  timeLabel.isNotEmpty ? timeLabel : 'Time pending',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMapSection(Map<String, dynamic> job) {
    final caregiverId =
        (job['caregiverId'] as String?) ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
    final userId = (job['userId'] as String?) ?? '';
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          child: LiveLocationMap(
            caregiverId: caregiverId,
            userId: userId,
            height: 220,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String personName,
    String service,
    String scheduledDate,
    String location,
    String timeLabel,
  ) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Person',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '$personName · $service',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 14,
                  color: Colors.black54,
                ),
                const SizedBox(width: 6),
                Text(
                  scheduledDate.isNotEmpty ? scheduledDate : 'Date pending',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  timeLabel.isNotEmpty ? timeLabel : 'Time pending',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notes',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                hintText: 'Add any job notes or completion summary',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: activityAccentBlue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceCard(String price, String status) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Price',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: activityPrimaryTextColor,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              status,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionButtons(String status) {
    if (_isUpdating) {
      return const [
        SizedBox(
          width: 160,
          height: 44,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final normalized = status.toUpperCase();
    if (normalized == 'ONGOING') {
      return [_ActionButton(label: 'Complete Job', onPressed: _completeJob)];
    }

    if (normalized == 'COMPLETED' || normalized == 'CANCELLED') {
      return const [
        Text(
          'Job already finalized',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ];
    }

    return [_ActionButton(label: 'Start Job', onPressed: _startJob)];
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

  Widget _surface({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _sectionBorderRadius,
        border: Border.all(color: _sectionBorderColor),
        boxShadow: [_sectionShadow],
      ),
      child: child,
    );
  }
}

class _JobStatusChip extends StatelessWidget {
  const _JobStatusChip({required this.status});

  final String status;

  String get _normalized => status.trim().toLowerCase();

  Color get _dotColor {
    switch (_normalized) {
      case 'ongoing':
      case 'in_progress':
        return Colors.blue.shade700;
      case 'assigned':
      case 'completed':
        return Colors.green.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String get _label {
    switch (_normalized) {
      case 'ongoing':
      case 'in_progress':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'assigned':
        return 'Assigned';
      default:
        return _formatLabel(status);
    }
  }

  String _formatLabel(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) return 'Scheduled';
    final segments = normalized
        .split(RegExp(r'[\s_-]+'))
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
              segment[0].toUpperCase() +
              (segment.length > 1 ? segment.substring(1).toLowerCase() : ''),
        )
        .toList();
    return segments.isEmpty ? 'Scheduled' : segments.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _sectionBorderColor),
        boxShadow: [_chipShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: activityAccentBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(160, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}
