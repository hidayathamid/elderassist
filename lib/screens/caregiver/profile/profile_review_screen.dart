import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _accentGold = Color(0xFFF4B63D);
const Color _cardShadowColor = Color(0x1A000000);
const Color _accentBlue = Color(0xFF00A8A7);
const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _profileDarkText,
);

const TextStyle _appBarTitleStyle = TextStyle(
  color: _profileDarkText,
  fontSize: 18,
  fontWeight: FontWeight.w600,
);

class ProfileReviewScreen extends StatefulWidget {
  const ProfileReviewScreen({super.key});

  @override
  State<ProfileReviewScreen> createState() => _ProfileReviewScreenState();
}

class _ProfileReviewScreenState extends State<ProfileReviewScreen> {
  int? _selectedRatingFilter;
  final Map<String, Future<_UserMini>> _userCache = <String, Future<_UserMini>>{};
  String? _savingReplyForReviewId;

  String _formatRelative(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo';
    if (diff.inDays >= 7) return '${diff.inDays ~/ 7}w';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'Now';
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    try {
      return DateFormat('yyyy-MM-dd').format(timestamp.toDate());
    } catch (_) {
      return '';
    }
  }

  int _coerceRating(dynamic value) {
    if (value is int) return value.clamp(1, 5);
    if (value is double) return value.round().clamp(1, 5);
    if (value is num) return value.toInt().clamp(1, 5);
    if (value is String) return (int.tryParse(value.trim()) ?? 0).clamp(1, 5);
    return 0;
  }

  Future<_UserMini> _fetchUserMini({
    required String userId,
    required String fallbackName,
  }) {
    if (userId.trim().isEmpty) {
      return Future<_UserMini>.value(_UserMini(name: fallbackName, photoUrl: null));
    }
    return _userCache.putIfAbsent(userId, () async {
      try {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final data = snap.data() ?? const <String, dynamic>{};
        final name = (data['name'] as String?)?.trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        return _UserMini(
          name: (name?.isNotEmpty == true) ? name! : fallbackName,
          photoUrl: (photoUrl?.isNotEmpty == true) ? photoUrl! : null,
        );
      } catch (_) {
        return _UserMini(name: fallbackName, photoUrl: null);
      }
    });
  }

  Future<void> _openReplySheet({
    required String reviewId,
    required String caregiverId,
    required String initialReply,
  }) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty || currentUserId != caregiverId) return;

    final controller = TextEditingController(text: initialReply);
    final focusNode = FocusNode();

    Future<void> save(BuildContext sheetContext) async {
      final reply = controller.text.trim();
      if (reply.isEmpty) return;
      if (_savingReplyForReviewId == reviewId) return;
      setState(() => _savingReplyForReviewId = reviewId);
      try {
        await FirebaseFirestore.instance.collection('reviews').doc(reviewId).set({
          'caregiverReply': reply,
          'caregiverReplyUpdatedAt': FieldValue.serverTimestamp(),
          'caregiverReplyAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) {
          Navigator.of(sheetContext).maybePop();
        }
      } catch (_) {
        // keep silent
      } finally {
        if (mounted) setState(() => _savingReplyForReviewId = null);
      }
    }

    Future<void> deleteReply(BuildContext sheetContext) async {
      if (initialReply.trim().isEmpty) return;
      if (_savingReplyForReviewId == reviewId) return;
      setState(() => _savingReplyForReviewId = reviewId);
      try {
        await FirebaseFirestore.instance.collection('reviews').doc(reviewId).set({
          'caregiverReply': FieldValue.delete(),
          'caregiverReplyUpdatedAt': FieldValue.delete(),
          'caregiverReplyAt': FieldValue.delete(),
        }, SetOptions(merge: true));
        if (mounted) {
          Navigator.of(sheetContext).maybePop();
        }
      } catch (_) {
        // keep silent
      } finally {
        if (mounted) setState(() => _savingReplyForReviewId = null);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                  boxShadow: const [
                    BoxShadow(
                      color: _cardShadowColor,
                      blurRadius: 18,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Reply to review',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: _profileDarkText,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).maybePop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black.withValues(alpha: 0.65),
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        maxLines: 4,
                        minLines: 3,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _profileDarkText,
                          height: 1.35,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Write a short reply…',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_savingReplyForReviewId == reviewId)
                            ? null
                            : () => save(sheetContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: Text(
                          initialReply.trim().isEmpty ? 'Send reply' : 'Update reply',
                        ),
                      ),
                    ),
                    if (initialReply.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: (_savingReplyForReviewId == reviewId)
                              ? null
                              : () => deleteReply(sheetContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(
                              color: Colors.red.shade200,
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: const Text('Delete reply'),
                        ),
                      ),
                    ],
                    SizedBox(height: math.max(MediaQuery.of(sheetContext).padding.bottom, 8)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    focusNode.dispose();
    controller.dispose();
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Colors.black.withValues(alpha: 0.12),
        width: 1.2,
      ),
      boxShadow: const [
        BoxShadow(
          color: _cardShadowColor,
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Widget _starRow(double rating, {double size = 16}) {
    final clamped = rating.clamp(0.0, 5.0);
    final full = clamped.floor();
    final half = (clamped - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;
    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star_rounded, size: size, color: _accentGold));
    }
    if (half == 1) {
      stars.add(Icon(Icons.star_half_rounded, size: size, color: _accentGold));
    }
    for (var i = 0; i < empty; i++) {
      stars.add(
        Icon(
          Icons.star_outline_rounded,
          size: size,
          color: Colors.black.withValues(alpha: 0.22),
        ),
      );
    }
    return Row(children: stars);
  }

  Widget _ratingBar({
    required int star,
    required int count,
    required int total,
  }) {
    final fraction = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            star.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.72),
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value:
                    (total > 0 && count > 0)
                        ? math.max(fraction, 0.03)
                        : 0.0,
                backgroundColor: Colors.black.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(_accentGold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Text(title, style: _sectionTitleStyle),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    Widget content = Text(label);
    final trimmed = label.trim();
    final firstToken = trimmed.split(' ').first;
    final rating = int.tryParse(firstToken);
    if (rating != null && rating >= 1 && rating <= 5) {
      var rest = trimmed.substring(firstToken.length).trim();
      if (rest.startsWith('★')) rest = rest.substring(1).trim();
      if (rest.startsWith('ミ.')) rest = rest.substring(2).trim();
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rating.toString()),
          const SizedBox(width: 4),
          const Icon(Icons.star_rounded, size: 14, color: _accentGold),
          if (rest.isNotEmpty) ...[const SizedBox(width: 4), Text(rest)],
        ],
      );
    }
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : _profileDarkText,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected
                ? _accentBlue.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        backgroundColor: selected ? _accentBlue : Colors.white,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
      child: content,
    );
  }

  Widget _buildUnavailablePlaceholder({
    required String message,
    String explanation = "It'll show up as soon as it becomes available.",
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSectionHeader(
          title: 'Reviews',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _cardDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 22,
                  color: _accentBlue,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: _profileDarkText,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewAvatar(_UserMini user) {
    final trimmed = user.photoUrl?.trim();
    if (trimmed?.isNotEmpty == true) {
      return ClipOval(
        child: SizedBox(
          width: 36,
          height: 36,
          child: SafeNetworkImage(
            trimmed!,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
        ),
      );
    }

    final name = user.name.trim();
    final initial = name.isEmpty ? 'U' : name[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.black.withValues(alpha: 0.08),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: _profileDarkText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final stream = caregiverId.isEmpty
        ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
            .collection('reviews')
            .where('caregiverId', isEqualTo: caregiverId)
            .snapshots();

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
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
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _profileDarkText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Reviews', style: _appBarTitleStyle),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (caregiverId.isEmpty) {
            return const Center(child: Text('Please sign in to view reviews.'));
          }
          if (snapshot.hasError) {
            return _buildUnavailablePlaceholder(
              message: 'Unable to load reviews.',
              explanation: 'Please check your connection and try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allDocs = snapshot.data!.docs.toList(growable: false)
            ..sort((a, b) {
              final ta = a.data()['createdAt'] as Timestamp?;
              final tb = b.data()['createdAt'] as Timestamp?;
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });
          if (allDocs.isEmpty) {
            return const Center(child: Text('No reviews yet.'));
          }

          final counts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
          var totalRating = 0;
          for (final doc in allDocs) {
            final rating = _coerceRating(doc.data()['rating']);
            if (rating <= 0) continue;
            counts[rating] = (counts[rating] ?? 0) + 1;
            totalRating += rating;
          }
          final totalCount = counts.values.fold<int>(0, (a, b) => a + b);
          final average = totalCount == 0 ? 0.0 : totalRating / totalCount;

          final selected = _selectedRatingFilter;
          final docs = selected == null
              ? allDocs
              : allDocs
                  .where((d) => _coerceRating(d.data()['rating']) == selected)
                  .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            physics: const BouncingScrollPhysics(),
            children: [
              Container(
                decoration: _cardDecoration(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 124,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            average.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: _profileDarkText,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _starRow(average, size: 16),
                          const SizedBox(height: 10),
                          Text(
                            '$totalCount ratings',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          for (final star in const [5, 4, 3, 2, 1]) ...[
                            _ratingBar(
                              star: star,
                              count: counts[star] ?? 0,
                              total: totalCount,
                            ),
                            if (star != 1) const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildSectionHeader(
                title: 'Filters',
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _filterChip(
                      label: 'All ($totalCount)',
                      selected: selected == null,
                      onTap: () => setState(() => _selectedRatingFilter = null),
                    ),
                    const SizedBox(width: 6),
                    for (final star in const [5, 4, 3, 2, 1]) ...[
                      _filterChip(
                        label: '$star (${counts[star] ?? 0})',
                        selected: selected == star,
                        onTap: () => setState(() => _selectedRatingFilter = star),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'No reviews for this filter.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data();
                  final personName =
                      (data['personName'] as String?)?.trim() ?? 'User';
                  final userId = (data['userId'] as String?)?.trim() ?? '';
                  final caregiverId = (data['caregiverId'] as String?)?.trim() ?? '';
                  final service = (data['service'] as String?)?.trim() ?? '';
                  final feedback = (data['feedback'] as String?)?.trim() ?? '';
                  final caregiverReply =
                      (data['caregiverReply'] as String?)?.trim() ?? '';
                  final rating = _coerceRating(data['rating']);
                  final createdAt = data['createdAt'] as Timestamp?;
                  final relative = _formatRelative(createdAt);
                  final dateLabel = _formatDate(createdAt);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: _cardDecoration(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<_UserMini>(
                            future: _fetchUserMini(
                              userId: userId,
                              fallbackName: personName,
                            ),
                            builder: (context, userSnap) {
                              final user =
                                  userSnap.data ??
                                  _UserMini(name: personName, photoUrl: null);
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _reviewAvatar(user),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      user.name.trim().isNotEmpty
                                          ? user.name.trim()
                                          : personName,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: _profileDarkText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _starRow(rating.toDouble(), size: 16),
                          if (service.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Service: $service',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.58),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            feedback.isNotEmpty ? feedback : 'No written feedback.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight:
                                  feedback.isNotEmpty
                                      ? FontWeight.w700
                                      : FontWeight.w700,
                              color:
                                  feedback.isNotEmpty
                                      ? _profileDarkText
                                      : Colors.black.withValues(alpha: 0.52),
                            ),
                          ),
                          if (caregiverReply.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'From caregiver',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black.withValues(alpha: 0.62),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    caregiverReply,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                      color: _profileDarkText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                relative.isNotEmpty ? relative : dateLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black.withValues(alpha: 0.45),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: (_savingReplyForReviewId == doc.id)
                                    ? null
                                    : () => _openReplySheet(
                                          reviewId: doc.id,
                                          caregiverId: caregiverId,
                                          initialReply: caregiverReply,
                                        ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _accentGold,
                                  minimumSize: const Size(0, 28),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: Text(
                                  caregiverReply.isEmpty ? 'Reply' : 'Edit reply',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _UserMini {
  const _UserMini({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;
}
