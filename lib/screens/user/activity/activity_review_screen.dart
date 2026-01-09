import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/activity_booking.dart';
import '../../../widgets/layout_constants.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../widgets/standard_app_bar.dart';

const Color _reviewAccent = Color(0xFFF4B63D);
const Color _labelColor = Color(0xFF1B1D29);
const Color _starFilledColor = Color(0xFF00A8A7);
const int _maxFeedbackChars = 200;

class ActivityReviewScreen extends StatefulWidget {
  const ActivityReviewScreen({
    super.key,
    required this.bookingId,
    required this.booking,
    this.caregiverData,
  });

  final String bookingId;
  final ActivityBooking booking;
  final Map<String, dynamic>? caregiverData;

  @override
  State<ActivityReviewScreen> createState() => _ActivityReviewScreenState();
}

class _ActivityReviewScreenState extends State<ActivityReviewScreen> {
  final TextEditingController _feedbackController = TextEditingController();
  int _rating = 5;
  int _initialRating = 5;
  bool _submitting = false;
  bool _hasChanges = false;

  String get _caregiverName {
    final name = (widget.caregiverData?['name'] as String?)?.trim();
    return (name != null && name.isNotEmpty) ? name : 'Caregiver';
  }

  String? get _caregiverPhoto {
    final photo = (widget.caregiverData?['photoUrl'] as String?)?.trim();
    return (photo != null && photo.isNotEmpty) ? photo : null;
  }

  @override
  void initState() {
    super.initState();
    _feedbackController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _feedbackController.removeListener(_onFieldChanged);
    _feedbackController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final dirty =
        _feedbackController.text.trim().isNotEmpty || _rating != _initialRating;
    if (dirty != _hasChanges) {
      setState(() => _hasChanges = dirty);
    }
  }

  Future<void> _updateCaregiverAverageRating() async {
    final caregiverId = widget.booking.caregiverId;
    if (caregiverId.isEmpty) return;
    final reviewsSnapshot = await FirebaseFirestore.instance
        .collection('reviews')
        .where('caregiverId', isEqualTo: caregiverId)
        .get();
    if (reviewsSnapshot.docs.isEmpty) return;
    double total = 0;
    int count = 0;
    for (final doc in reviewsSnapshot.docs) {
      final ratingValue = (doc.data()['rating'] as num?)?.toDouble();
      if (ratingValue != null) {
        total += ratingValue;
        count++;
      }
    }
    if (count == 0) return;
    final average = double.parse((total / count).toStringAsFixed(1));
    await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId)
        .set({'rating': average}, SetOptions(merge: true));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _submitting = true);
    final feedback = _feedbackController.text.trim();
    try {
      await FirebaseFirestore.instance.collection('reviews').add({
        'bookingId': widget.bookingId,
        'caregiverId': widget.booking.caregiverId,
        'userId': user.uid,
        'rating': _rating,
        'feedback': feedback,
        'service': widget.booking.service,
        'personName': widget.booking.personName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _updateCaregiverAverageRating();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _feedbackController.clear();
        _initialRating = _rating;
        _hasChanges = false;
      });
      Navigator.of(context).pop('history');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to submit review. Please try again.'),
        ),
      );
    }
  }

  Future<bool> _confirmExit() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Discard review?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You have unsent feedback. Leave without submitting?',
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _reviewAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Leave'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmExit();
    if (!shouldLeave || !mounted) return false;
    Navigator.of(context).pop('history');
    return false;
  }

  Widget _buildStarRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final value = index + 1;
        final filled = value <= _rating;
        return IconButton(
          onPressed: () {
            setState(() => _rating = value);
            _onFieldChanged();
          },
          iconSize: 26,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            color: filled ? _starFilledColor : Colors.grey.shade300,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedbackLength = _feedbackController.text.characters.length;
    final theme = Theme.of(context);

    final header = Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey.shade100,
          child: ClipOval(
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Text(
                      _caregiverName.isNotEmpty
                          ? _caregiverName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  if (_caregiverPhoto?.trim().isNotEmpty == true)
                    SafeNetworkImage(
                      _caregiverPhoto!.trim(),
                      fit: BoxFit.cover,
                      placeholder: const SizedBox.shrink(),
                      errorWidget: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _caregiverName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: _labelColor,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.medical_services_outlined,
              size: 13,
              color: Colors.black45,
            ),
            const SizedBox(width: 4),
            Text(
              widget.booking.service,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            widget.booking.personName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        header,
        const SizedBox(height: 20),
        Text(
          'How was your treatment experience?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        _buildStarRow(),
        const SizedBox(height: 16),
        Divider(color: Colors.grey.shade200, height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RichText(
              text: TextSpan(
                text: 'Tell your experience ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                children: const [
                  TextSpan(
                    text: '(optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$feedbackLength/$_maxFeedbackChars',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade50,
          ),
          child: TextField(
            controller: _feedbackController,
            maxLength: _maxFeedbackChars,
            maxLines: 5,
            minLines: 5,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Share your feedback...',
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );

    return WillPopScope(
      onWillPop: _handleBackPress,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: buildProfileStyleAppBar(
          title: 'Add a Review',
          onBack: () => _handleBackPress(),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: kStandardScreenPadding,
                  child: content,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.disabled)) {
                          return Colors.grey.shade300;
                        }
                        return _reviewAccent;
                      }),
                      foregroundColor: const WidgetStatePropertyAll<Color>(
                        Colors.black,
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 12),
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
