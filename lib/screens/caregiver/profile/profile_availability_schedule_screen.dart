import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../ui_tokens.dart';
import 'add_blocked_date_screen.dart';
import 'profile_availability_shared.dart';
import 'reschedule_booking_screen.dart';

class ProfileAvailabilityScheduleScreen extends StatefulWidget {
  const ProfileAvailabilityScheduleScreen({super.key});

  @override
  State<ProfileAvailabilityScheduleScreen> createState() =>
      _ProfileAvailabilityScheduleScreenState();
}

class _ProfileAvailabilityScheduleScreenState
    extends State<ProfileAvailabilityScheduleScreen> {
  bool _cleanupBlockedDatesInFlight = false;

  DocumentReference<Map<String, dynamic>>? get _docRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('availability').doc(uid);
  }

  DateTime _normalizeDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  List<BlockedDate> _removeExpiredBlockedDates(List<BlockedDate> current) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return current.where((entry) {
      final end = entry.end;
      if (end == null) return true;
      return !_normalizeDay(end).isBefore(today);
    }).toList();
  }

  void _scheduleExpiredBlockedDatesCleanup(List<BlockedDate> current) {
    if (_cleanupBlockedDatesInFlight) return;
    final cleaned = _removeExpiredBlockedDates(current);
    if (cleaned.length == current.length) return;

    _cleanupBlockedDatesInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _updateAvailability(blockedDates: cleaned);
      } finally {
        _cleanupBlockedDatesInFlight = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final docRef = _docRef;
    if (docRef == null) {
      return Scaffold(
        backgroundColor: Colors.white,
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
          title: const Text(
            'Availability',
            style: availabilityAppBarTitleStyle,
          ),
        ),
        body: const Center(
          child: Text(
            'Sign in to manage availability.',
            style: availabilityBodyTextStyle,
          ),
        ),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: Colors.white,
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
        title: const Text(
          'Availability schedule',
          style: availabilityAppBarTitleStyle,
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: availabilityDarkText,
            size: UiTokens.icon20,
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Unable to load availability: ${snapshot.error}',
                  style: availabilityBodyTextStyle,
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: availabilityTealAccent),
              );
            }

             final data = snapshot.data?.data();
             final weeklySchedule = _weeklyFromSnapshot(data);
             final blockedDates = _blockedDatesFromSnapshot(data);
             _scheduleExpiredBlockedDatesCleanup(blockedDates);

             return SingleChildScrollView(
               padding: const EdgeInsets.fromLTRB(
                 UiTokens.s16,
                UiTokens.s12,
                UiTokens.s16,
                UiTokens.s24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: UiTokens.s6),
                  _buildTimelineSection(weeklySchedule),
                  const SizedBox(height: UiTokens.s10),
                  _buildBlockedDatesSection(blockedDates),
                  const SizedBox(height: UiTokens.s24),
                ],
              ),
            );
          },
        ),
      ),
    );
    return scaffold;
  }

  BoxDecoration _sectionCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(UiTokens.r18),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: availabilityPrimaryCardShadow(),
    );
  }

  Widget _buildTimelineSection(List<DaySchedule> schedule) {
    return Container(
      decoration: _sectionCardDecoration(),
      padding: const EdgeInsets.fromLTRB(
        UiTokens.s16,
        UiTokens.s12,
        UiTokens.s16,
        UiTokens.s14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Weekly timeline',
                  style: availabilitySectionHeaderStyle,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RescheduleBookingScreen(
                      initialSchedule: schedule,
                      onSave: (updated) async {
                        await _updateAvailability(weeklySchedule: updated);
                      },
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: UiTokens.s4,
                    vertical: UiTokens.s2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                  foregroundColor: availabilityTealAccent,
                  textStyle: availabilityBodySemiBoldTextStyle,
                ),
                child: const Text('+ Edit'),
              ),
            ],
          ),
          const SizedBox(height: UiTokens.s10),
          Column(
            children: schedule
                .map((entry) => _buildTimelineEntry(entry))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineEntry(DaySchedule entry) {
    final isAvailable = entry.available;
    final offlineColor = availabilityDarkText.withValues(alpha: 0.6);
    final statusColor = isAvailable ? availabilityTealAccent : offlineColor;
    final icon = isAvailable ? Icons.schedule : Icons.block;
    final label = isAvailable ? entry.rangeLabel : 'Not available';

    return Container(
      margin: const EdgeInsets.only(bottom: UiTokens.s8),
      padding: const EdgeInsets.all(UiTokens.s10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: availabilitySecondaryCardShadow(),
      ),
      child: Row(
        children: [
          Container(
            width: UiTokens.s4,
            height: UiTokens.serviceH,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(UiTokens.r12),
            ),
          ),
          const SizedBox(width: UiTokens.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.day, style: availabilityBodySemiBoldTextStyle),
                const SizedBox(height: UiTokens.s4),
                Row(
                  children: [
                    Icon(icon, size: UiTokens.icon16, color: statusColor),
                    const SizedBox(width: UiTokens.s6),
                    Text(
                      label,
                      style: availabilitySmallTextStyle.copyWith(
                        color: isAvailable
                            ? availabilityDarkText
                            : offlineColor,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            isAvailable ? 'Available' : 'Offline',
            style: availabilitySmallTextStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedDatesSection(List<BlockedDate> blockedDates) {
    return Container(
      decoration: _sectionCardDecoration(),
      padding: const EdgeInsets.fromLTRB(
        UiTokens.s16,
        UiTokens.s12,
        UiTokens.s16,
        UiTokens.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Blocked dates',
                  style: availabilitySectionHeaderStyle,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddBlockedDateScreen(
                      onSave: (newEntry) async {
                        await _updateAvailability(
                          blockedDates: [...blockedDates, newEntry],
                        );
                      },
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                  foregroundColor: availabilityTealAccent,
                  textStyle: availabilityBodySemiBoldTextStyle,
                ),
                child: const Text('+ Add'),
              ),
            ],
          ),
          const SizedBox(height: UiTokens.s10),
          if (blockedDates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
              child: Text(
                'Any blocked dates will appear here.',
                style: availabilitySmallTextStyle.copyWith(
                  color: mutedAvailabilityTextColor(),
                ),
              ),
            )
          else
            Wrap(
              spacing: UiTokens.s8,
              runSpacing: UiTokens.s10,
              children: blockedDates
                  .map((entry) => _blockedDateCard(entry, blockedDates))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _blockedDateCard(BlockedDate entry, List<BlockedDate> blockedDates) {
    return Container(
      padding: const EdgeInsets.all(UiTokens.s10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: UiTokens.icon16,
                color: availabilityTealAccent,
              ),
              const SizedBox(width: UiTokens.s6),
              Expanded(
                child: Text(
                  entry.displayLabel,
                  style: availabilityBodySemiBoldTextStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: UiTokens.s6),
              InkWell(
                onTap: () => _removeBlockedDate(entry, blockedDates),
                borderRadius: BorderRadius.circular(UiTokens.r12),
                child: Icon(
                  Icons.close,
                  size: UiTokens.icon16,
                  color: mutedAvailabilityTextColor(),
                ),
              ),
            ],
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: UiTokens.s6),
            Text(
              entry.description,
              style: availabilitySmallTextStyle.copyWith(
                color: mutedAvailabilityTextColor(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removeBlockedDate(
    BlockedDate entry,
    List<BlockedDate> current,
  ) async {
    final updated = List<BlockedDate>.from(current)..remove(entry);
    await _updateAvailability(blockedDates: updated);
  }

  Future<void> _updateAvailability({
    List<DaySchedule>? weeklySchedule,
    List<BlockedDate>? blockedDates,
  }) async {
    final ref = _docRef;
    if (ref == null) return;
    final updates = <String, dynamic>{};
    if (weeklySchedule != null) {
      updates['weeklySchedule'] = weeklySchedule
          .map((entry) => entry.toMap())
          .toList();
    }
    if (blockedDates != null) {
      updates['blockedDates'] = blockedDates
          .map((entry) => entry.toMap())
          .toList();
    }
    if (updates.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      updates['caregiverId'] = uid;
    }
    await ref.set(updates, SetOptions(merge: true));
  }

  List<DaySchedule> _weeklyFromSnapshot(Map<String, dynamic>? data) {
    final raw = data?['weeklySchedule'];
    if (raw is Iterable) {
      final parsed = <String, DaySchedule>{};
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final day = entry['day'] as String?;
          if (day == null || day.isEmpty) {
            continue;
          }
          final defaultEntry = defaultScheduleLookup[day];
          final start =
              entry['start'] as String? ?? defaultEntry?.start ?? '08:00';
          final end = entry['end'] as String? ?? defaultEntry?.end ?? '18:00';
          parsed[day] = DaySchedule(
            day: day,
            available:
                entry['available'] as bool? ?? defaultEntry?.available ?? true,
            start: start,
            end: end,
          );
        }
      }
      return defaultWeeklySchedule
          .map((entry) => parsed[entry.day] ?? entry)
          .toList();
    }
    return defaultWeeklySchedule.toList();
  }

  List<BlockedDate> _blockedDatesFromSnapshot(Map<String, dynamic>? data) {
    final raw = data?['blockedDates'];
    if (raw is Iterable) {
      return raw
          .map((entry) {
            if (entry is Map<String, dynamic>) {
              final start = _tryParseDate(entry['start'] as String?);
              final end = _tryParseDate(entry['end'] as String?);
              final description = entry['description'] as String? ?? '';
              final fallback = entry['label'] as String?;
              if (start == null || end == null) {
                if (fallback == null) return null;
              }
              return BlockedDate(
                start: start,
                end: end,
                description: description,
                fallbackLabel: fallback,
              );
            }
            return null;
          })
          .whereType<BlockedDate>()
          .toList();
    }
    return [];
  }

  DateTime? _tryParseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}
