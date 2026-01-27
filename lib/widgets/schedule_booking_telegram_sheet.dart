import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ScheduleBookingResult {
  const ScheduleBookingResult({
    required this.day,
    required this.start,
    required this.end,
  });

  final DateTime day;
  final TimeOfDay start;
  final TimeOfDay end;
}

class _WeeklyTimeRange {
  const _WeeklyTimeRange({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

Future<ScheduleBookingResult?> showScheduleBookingTelegramSheet({
  required BuildContext context,
  required String caregiverId,
  required DateTime initialDay,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
  required Color primaryColor,
  String? excludeBookingId,
  bool allowInitialDayEvenIfUnavailable = false,
  bool enableDrag = false,
  Color? barrierColor,
}) {
  final initialSelected = DateTime(
    initialDay.year,
    initialDay.month,
    initialDay.day,
    initialStart.hour,
    initialStart.minute,
  );

  return showModalBottomSheet<ScheduleBookingResult>(
    context: context,
    isScrollControlled: true,
    enableDrag: enableDrag,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.54),
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final availabilityFuture = FirebaseFirestore.instance
          .collection('availability')
          .doc(caregiverId)
          .get();

      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: availabilityFuture,
        builder: (context, snapshot) {
          const sheetBg = Colors.white;
          const sheetRadius = Radius.circular(28);

          final ButtonStyle schedulePrimaryButtonStyle = ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.grey.shade300;
              }
              return primaryColor;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.grey.shade600;
              }
              return Colors.black;
            }),
            elevation: WidgetStateProperty.resolveWith<double>((states) {
              if (states.contains(WidgetState.disabled)) return 0;
              return 2;
            }),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 14),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          );

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: sheetBg,
                  borderRadius: BorderRadius.vertical(top: sheetRadius),
                ),
                child: const SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 6),
                        SizedBox(
                          width: 36,
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0x33FFFFFF),
                              borderRadius: BorderRadius.all(
                                Radius.circular(24),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Schedule booking',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 18),
                        SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final blockedRanges = _parseBlockedDateRanges(data['blockedDates']);
          final disabledWeekdays = _parseUnavailableWeekdays(
            data['weeklySchedule'],
          );
          final weeklyRanges = _parseWeeklyTimeRanges(data['weeklySchedule']);

          DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
          final pinnedDay = normalize(initialDay);

          bool isBlocked(DateTime day) {
            final date = normalize(day);
            for (final range in blockedRanges) {
              final start = normalize(range.start);
              final end = normalize(range.end);
              if (!date.isBefore(start) && !date.isAfter(end)) return true;
            }
            return false;
          }

          bool isAvailableDay(DateTime day) {
            final date = normalize(day);
            final today = normalize(DateTime.now());
            if (allowInitialDayEvenIfUnavailable && date == pinnedDay) {
              return true;
            }
            if (!date.isAfter(today)) return false;
            if (disabledWeekdays.contains(date.weekday)) return false;
            if (isBlocked(date)) return false;
            if (!weeklyRanges.containsKey(date.weekday)) return false;
            return true;
          }

          final today = normalize(DateTime.now());
          final availableDays = <DateTime>[];
          for (int i = 0; i < 180; i++) {
            final day = today.add(Duration(days: i));
            if (isAvailableDay(day)) availableDays.add(day);
            if (availableDays.length >= 120) break;
          }

          DateTime selectedDay = normalize(initialDay);
          if (!isAvailableDay(selectedDay)) {
            selectedDay = availableDays.isNotEmpty
                ? availableDays.first
                : today;
          }
          DateTime visibleMonth = DateTime(selectedDay.year, selectedDay.month);

          TimeOfDay alignTimeToInterval(TimeOfDay t, int intervalMinutes) {
            if (intervalMinutes <= 1) return t;
            final total = (t.hour * 60) + t.minute;
            final rounded =
                ((total + intervalMinutes - 1) ~/ intervalMinutes) *
                intervalMinutes;
            final clamped = rounded.clamp(0, 24 * 60 - 1);
            return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
          }

          TimeOfDay selectedTime = alignTimeToInterval(
            TimeOfDay.fromDateTime(initialSelected),
            15,
          );
          TimeOfDay selectedEndTime = initialEnd;

          int toMinutes(TimeOfDay t) => (t.hour * 60) + t.minute;
          TimeOfDay fromMinutes(int minutes) {
            final clamped = minutes.clamp(0, 24 * 60 - 1);
            return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
          }

          TimeOfDay ensureEndTime(
            TimeOfDay start,
            TimeOfDay currentEnd,
            TimeOfDay latestAllowed,
          ) {
            final minEnd = fromMinutes(toMinutes(start) + 15);
            if (toMinutes(latestAllowed) <= toMinutes(minEnd)) {
              return latestAllowed;
            }
            if (toMinutes(currentEnd) < toMinutes(minEnd)) return minEnd;
            if (toMinutes(currentEnd) > toMinutes(latestAllowed)) {
              return latestAllowed;
            }
            return currentEnd;
          }

          String ymd(DateTime d) {
            final y = d.year.toString().padLeft(4, '0');
            final m = d.month.toString().padLeft(2, '0');
            final day = d.day.toString().padLeft(2, '0');
            return '$y-$m-$day';
          }

          bool overlapsMinutes(int startA, int endA, int startB, int endB) {
            final aStart = min(startA, endA);
            final aEnd = max(startA, endA);
            final bStart = min(startB, endB);
            final bEnd = max(startB, endB);
            return max(aStart, bStart) < min(aEnd, bEnd);
          }

          bool rangeOverlapsTaken(
            int startMin,
            int endMin,
            List<DateTimeRange> taken,
          ) {
            for (final r in taken) {
              final s = r.start.hour * 60 + r.start.minute;
              final e = r.end.hour * 60 + r.end.minute;
              if (overlapsMinutes(startMin, endMin, s, e)) return true;
            }
            return false;
          }

          const monthNames = [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
          const weekdayHeaders = [
            'MON',
            'TUE',
            'WED',
            'THU',
            'FRI',
            'SAT',
            'SUN',
          ];

          String timeLabel(TimeOfDay t) {
            final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
            final minute = t.minute.toString().padLeft(2, '0');
            final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
            return '$hour12:$minute $suffix';
          }

          TimeOfDay? parseStoredTime(String? raw) {
            if (raw == null) return null;
            final v = raw.trim();
            if (v.isEmpty) return null;
            final match = RegExp(
              r'^(\d{1,2}):(\d{2})(?:\s*([aApP][mM]))?$',
            ).firstMatch(v);
            if (match == null) return null;
            final hour = int.tryParse(match.group(1) ?? '');
            final minute = int.tryParse(match.group(2) ?? '');
            if (hour == null || minute == null) return null;
            if (minute < 0 || minute > 59) return null;
            final suffix = (match.group(3) ?? '').toUpperCase();
            if (suffix.isEmpty) {
              if (hour < 0 || hour > 23) return null;
              return TimeOfDay(hour: hour, minute: minute);
            }
            if (hour < 1 || hour > 12) return null;
            int h = hour % 12;
            if (suffix == 'PM') h += 12;
            return TimeOfDay(hour: h, minute: minute);
          }

          final takenCache = <String, List<DateTimeRange>>{};
          final loadingTaken = <String>{};

          Future<List<DateTimeRange>> fetchTakenRanges(DateTime day) async {
            final key = ymd(day);
            try {
              final snap = await FirebaseFirestore.instance
                  .collection('bookings')
                  .where('caregiverId', isEqualTo: caregiverId)
                  .where('date', isEqualTo: key)
                  .where('paymentStatus', isEqualTo: 'PAID')
                  .where('status', whereIn: const ['ASSIGNED', 'SCHEDULED'])
                  .get();

              final ranges = <DateTimeRange>[];
              for (final doc in snap.docs) {
                if (excludeBookingId != null && doc.id == excludeBookingId) {
                  continue;
                }
                final booking = doc.data();
                final start = parseStoredTime(booking['startTime']?.toString());
                final end = parseStoredTime(booking['endTime']?.toString());
                if (start == null || end == null) continue;
                if (toMinutes(end) <= toMinutes(start)) continue;
                ranges.add(
                  DateTimeRange(
                    start: DateTime(2000, 1, 1, start.hour, start.minute),
                    end: DateTime(2000, 1, 1, end.hour, end.minute),
                  ),
                );
              }

              ranges.sort((a, b) => a.start.compareTo(b.start));
              return ranges;
            } catch (_) {
              return const <DateTimeRange>[];
            }
          }

          List<TimeOfDay> generateSlotsInclusiveEnd({
            required TimeOfDay start,
            required TimeOfDay end,
            required int minuteInterval,
          }) {
            final startMinutes = toMinutes(start);
            final endMinutes = toMinutes(end);
            if (minuteInterval <= 0 || endMinutes < startMinutes) {
              return const [];
            }

            int first = startMinutes;
            if (first % minuteInterval != 0) {
              first = ((first ~/ minuteInterval) + 1) * minuteInterval;
            }
            int last = endMinutes;
            last = (last ~/ minuteInterval) * minuteInterval;
            if (last < first) return const [];

            final slots = <TimeOfDay>[];
            for (int m = first; m <= last; m += minuteInterval) {
              slots.add(TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
            }
            return slots;
          }

          return StatefulBuilder(
            builder: (context, setModalState) {
              final dayRange = weeklyRanges[selectedDay.weekday];

              final selectedKey = ymd(selectedDay);
              final takenRanges =
                  takenCache[selectedKey] ?? const <DateTimeRange>[];
              if (!takenCache.containsKey(selectedKey) &&
                  !loadingTaken.contains(selectedKey)) {
                loadingTaken.add(selectedKey);
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  final next = await fetchTakenRanges(selectedDay);
                  if (!ctx.mounted) return;
                  setModalState(() {
                    takenCache[selectedKey] = next;
                    loadingTaken.remove(selectedKey);
                  });
                });
              }

              bool isRangeFree(TimeOfDay start, TimeOfDay end) {
                final s = toMinutes(start);
                final e = toMinutes(end);
                if (e <= s) return false;
                return !rangeOverlapsTaken(s, e, takenRanges);
              }

              List<TimeOfDay> startSlots = dayRange == null
                  ? const <TimeOfDay>[]
                  : _generateTimeSlots(
                      start: dayRange.start,
                      end: dayRange.end,
                      minuteInterval: 15,
                    );

              if (dayRange != null) {
                final maxStartMin = toMinutes(dayRange.end) - 15;
                startSlots = startSlots
                    .where((t) => toMinutes(t) <= maxStartMin)
                    .toList();
              }

              List<TimeOfDay> endOptionsFor(TimeOfDay start) {
                if (dayRange == null) return const <TimeOfDay>[];
                final minEnd = fromMinutes(toMinutes(start) + 15);
                return generateSlotsInclusiveEnd(
                  start: minEnd,
                  end: dayRange.end,
                  minuteInterval: 15,
                );
              }

              bool isStartEnabled(TimeOfDay start) =>
                  isRangeFree(start, fromMinutes(toMinutes(start) + 15));
              bool isEndEnabled(TimeOfDay start, TimeOfDay end) =>
                  isRangeFree(start, end);

              if (startSlots.isNotEmpty) {
                final stillExists = startSlots.any(
                  (t) =>
                      t.hour == selectedTime.hour &&
                      t.minute == selectedTime.minute,
                );
                final firstEnabled = startSlots.firstWhere(
                  isStartEnabled,
                  orElse: () => startSlots.first,
                );
                if (!stillExists || !isStartEnabled(selectedTime)) {
                  selectedTime = firstEnabled;
                }
              }

              final endSlots = endOptionsFor(selectedTime);
              if (endSlots.isNotEmpty) {
                final minEnd = fromMinutes(toMinutes(selectedTime) + 15);
                final stillExists = endSlots.any(
                  (t) =>
                      t.hour == selectedEndTime.hour &&
                      t.minute == selectedEndTime.minute,
                );
                final validOrder =
                    toMinutes(selectedEndTime) >= toMinutes(minEnd);
                final firstEnabled = endSlots.firstWhere(
                  (t) => isEndEnabled(selectedTime, t),
                  orElse: () => endSlots.first,
                );
                if (!stillExists ||
                    !validOrder ||
                    !isEndEnabled(selectedTime, selectedEndTime)) {
                  selectedEndTime = firstEnabled;
                }
              }

              void shiftMonth(int delta) {
                visibleMonth = DateTime(
                  visibleMonth.year,
                  visibleMonth.month + delta,
                );
              }

              Widget settingRow({
                required String label,
                required String value,
                required VoidCallback onTap,
                required bool enabled,
              }) {
                return InkWell(
                  onTap: enabled ? onTap : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? Colors.black87
                                  : Colors.black.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: enabled
                                  ? Colors.black87
                                  : Colors.black.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final firstOfMonth = DateTime(
                visibleMonth.year,
                visibleMonth.month,
                1,
              );
              final daysInMonth = DateUtils.getDaysInMonth(
                visibleMonth.year,
                visibleMonth.month,
              );
              final leadingEmpty = firstOfMonth.weekday - 1;
              final itemCount = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
              final canPickStart = startSlots.any(isStartEnabled);
              final canPickEnd = endSlots.any(
                (t) => isEndEnabled(selectedTime, t),
              );
              final canSubmit =
                  availableDays.isNotEmpty && canPickStart && canPickEnd;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: sheetBg,
                    borderRadius: BorderRadius.vertical(top: sheetRadius),
                  ),
                  child: SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.92,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.black87,
                                  ),
                                  splashRadius: 20,
                                ),
                                const Expanded(
                                  child: Text(
                                    'Schedule booking',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 48),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setModalState(() => shiftMonth(-1)),
                                  icon: const Icon(
                                    Icons.chevron_left_rounded,
                                    color: Colors.black54,
                                  ),
                                  splashRadius: 18,
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setModalState(() => shiftMonth(1)),
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.black54,
                                  ),
                                  splashRadius: 18,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                for (final label in weekdayHeaders)
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: itemCount,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 6,
                                  ),
                              itemBuilder: (context, index) {
                                final cellIndex = index - leadingEmpty;
                                if (cellIndex < 0 || cellIndex >= daysInMonth) {
                                  return const SizedBox.shrink();
                                }
                                final dayNumber = cellIndex + 1;
                                final date = DateTime(
                                  visibleMonth.year,
                                  visibleMonth.month,
                                  dayNumber,
                                );

                                final bool isPinned =
                                    allowInitialDayEvenIfUnavailable &&
                                    normalize(date) == pinnedDay;
                                if (isBlocked(date) && !isPinned) {
                                  return const SizedBox.shrink();
                                }

                                final available = isAvailableDay(date);
                                final selected =
                                    date.year == selectedDay.year &&
                                    date.month == selectedDay.month &&
                                    date.day == selectedDay.day;

                                final textColor = available
                                    ? Colors.black87
                                    : Colors.black.withValues(alpha: 0.20);

                                return GestureDetector(
                                  onTap: available
                                      ? () => setModalState(() {
                                          selectedDay = date;
                                          visibleMonth = DateTime(
                                            date.year,
                                            date.month,
                                          );
                                          final range =
                                              weeklyRanges[date.weekday];
                                          final daySlots = range == null
                                              ? const <TimeOfDay>[]
                                              : _generateTimeSlots(
                                                  start: range.start,
                                                  end: range.end,
                                                  minuteInterval: 15,
                                                );
                                          if (daySlots.isNotEmpty) {
                                            selectedTime = daySlots.first;
                                          }
                                          if (range != null) {
                                            selectedEndTime = ensureEndTime(
                                              selectedTime,
                                              selectedEndTime,
                                              range.end,
                                            );
                                          }
                                        })
                                      : null,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? primaryColor
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        dayNumber.toString(),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: selected
                                              ? Colors.black
                                              : textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: Colors.black12),

                          if (takenRanges.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
                              child: Text(
                                'Taken: ${takenRanges.map((r) => '${timeLabel(TimeOfDay.fromDateTime(r.start))} - ${timeLabel(TimeOfDay.fromDateTime(r.end))}').join(', ')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          settingRow(
                            label: 'Select time',
                            value:
                                '${timeLabel(selectedTime)} - ${timeLabel(selectedEndTime)}',
                            enabled: canSubmit,
                            onTap: () async {
                              if (dayRange == null) return;

                              await showGeneralDialog<void>(
                                context: context,
                                barrierDismissible: true,
                                barrierLabel: 'Select time',
                                barrierColor: Colors.black.withValues(
                                  alpha: 0.55,
                                ),
                                transitionDuration: const Duration(
                                  milliseconds: 180,
                                ),
                                pageBuilder: (context, animation, secondaryAnimation) {
                                  TimeOfDay localStart = selectedTime;
                                  TimeOfDay localEnd = selectedEndTime;

                                  return StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      final startOptions = startSlots;

                                      TimeOfDay pickFirstEnabledStart() {
                                        return startOptions.firstWhere(
                                          isStartEnabled,
                                          orElse: () => startOptions.first,
                                        );
                                      }

                                      if (!startOptions.any(
                                        (t) =>
                                            t.hour == localStart.hour &&
                                            t.minute == localStart.minute,
                                      )) {
                                        localStart = pickFirstEnabledStart();
                                      }
                                      if (!isStartEnabled(localStart)) {
                                        localStart = pickFirstEnabledStart();
                                      }

                                      final endOptions = endOptionsFor(
                                        localStart,
                                      );

                                      TimeOfDay pickFirstEnabledEnd() {
                                        return endOptions.firstWhere(
                                          (t) => isEndEnabled(localStart, t),
                                          orElse: () => endOptions.first,
                                        );
                                      }

                                      if (endOptions.isNotEmpty) {
                                        if (!endOptions.any(
                                          (t) =>
                                              t.hour == localEnd.hour &&
                                              t.minute == localEnd.minute,
                                        )) {
                                          localEnd = pickFirstEnabledEnd();
                                        }
                                        if (!isEndEnabled(
                                          localStart,
                                          localEnd,
                                        )) {
                                          localEnd = pickFirstEnabledEnd();
                                        }
                                      }

                                      final startIndex = max(
                                        0,
                                        startOptions.indexWhere(
                                          (t) =>
                                              t.hour == localStart.hour &&
                                              t.minute == localStart.minute,
                                        ),
                                      );
                                      final endIndex = max(
                                        0,
                                        endOptions.indexWhere(
                                          (t) =>
                                              t.hour == localEnd.hour &&
                                              t.minute == localEnd.minute,
                                        ),
                                      );

                                      final startController =
                                          FixedExtentScrollController(
                                            initialItem: startIndex,
                                          );
                                      final endController =
                                          FixedExtentScrollController(
                                            initialItem: endIndex,
                                          );

                                      const dialogTitleStyle = TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                        decoration: TextDecoration.none,
                                        letterSpacing: 0,
                                        height: 1.0,
                                      );
                                      const dialogLabelStyle = TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                        decoration: TextDecoration.none,
                                        letterSpacing: 0,
                                        height: 1.0,
                                      );

                                      return Theme(
                                        data: Theme.of(ctx),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: Center(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              child: BackdropFilter(
                                                filter: ui.ImageFilter.blur(
                                                  sigmaX: 14,
                                                  sigmaY: 14,
                                                ),
                                                child: Container(
                                                  width: 340,
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        16,
                                                        14,
                                                        16,
                                                        10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: sheetBg.withValues(
                                                      alpha: 0.98,
                                                    ),
                                                    border: Border.all(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.10,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Text(
                                                        'Select time',
                                                        style: dialogTitleStyle,
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Start',
                                                          style:
                                                              dialogLabelStyle,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        height: 150,
                                                        child: CupertinoTheme(
                                                          data:
                                                              const CupertinoThemeData(
                                                                brightness:
                                                                    Brightness
                                                                        .light,
                                                              ),
                                                          child: CupertinoPicker(
                                                            scrollController:
                                                                startController,
                                                            itemExtent: 36,
                                                            magnification: 1.08,
                                                            useMagnifier: true,
                                                            onSelectedItemChanged:
                                                                (index) {
                                                                  final picked =
                                                                      startOptions[index];
                                                                  setDialogState(
                                                                    () {
                                                                      localStart =
                                                                          picked;
                                                                    },
                                                                  );
                                                                },
                                                            children: [
                                                              for (final t
                                                                  in startOptions)
                                                                Center(
                                                                  child: Text(
                                                                    timeLabel(
                                                                      t,
                                                                    ),
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          18,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      color:
                                                                          isStartEnabled(
                                                                            t,
                                                                          )
                                                                          ? Colors.black87
                                                                          : Colors.black.withValues(
                                                                              alpha: 0.35,
                                                                            ),
                                                                      decoration:
                                                                          TextDecoration
                                                                              .none,
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'End',
                                                          style:
                                                              dialogLabelStyle,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        height: 150,
                                                        child: CupertinoTheme(
                                                          data:
                                                              const CupertinoThemeData(
                                                                brightness:
                                                                    Brightness
                                                                        .light,
                                                              ),
                                                          child: CupertinoPicker(
                                                            key: ValueKey(
                                                              '${localStart.hour}:${localStart.minute}',
                                                            ),
                                                            scrollController:
                                                                endController,
                                                            itemExtent: 36,
                                                            magnification: 1.08,
                                                            useMagnifier: true,
                                                            onSelectedItemChanged:
                                                                (index) {
                                                                  final picked =
                                                                      endOptions[index];
                                                                  setDialogState(
                                                                    () {
                                                                      localEnd =
                                                                          picked;
                                                                    },
                                                                  );
                                                                },
                                                            children: [
                                                              for (final t
                                                                  in endOptions)
                                                                Center(
                                                                  child: Text(
                                                                    timeLabel(
                                                                      t,
                                                                    ),
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          18,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      color:
                                                                          isEndEnabled(
                                                                            localStart,
                                                                            t,
                                                                          )
                                                                          ? Colors.black87
                                                                          : Colors.black.withValues(
                                                                              alpha: 0.35,
                                                                            ),
                                                                      decoration:
                                                                          TextDecoration
                                                                              .none,
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        child: ElevatedButton(
                                                          onPressed: () {
                                                            if (!isStartEnabled(
                                                                  localStart,
                                                                ) ||
                                                                !isEndEnabled(
                                                                  localStart,
                                                                  localEnd,
                                                                )) {
                                                              ScaffoldMessenger.of(
                                                                ctx,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    'That time range is already taken. Please choose another slot.',
                                                                  ),
                                                                  behavior:
                                                                      SnackBarBehavior
                                                                          .floating,
                                                                ),
                                                              );
                                                              return;
                                                            }
                                                            Navigator.of(
                                                              context,
                                                            ).pop();
                                                            setModalState(() {
                                                              selectedTime =
                                                                  localStart;
                                                              selectedEndTime =
                                                                  localEnd;
                                                            });
                                                          },
                                                          style:
                                                              schedulePrimaryButtonStyle,
                                                          child: const Text(
                                                            'Done',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                transitionBuilder:
                                    (context, animation, _, child) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale:
                                              Tween<double>(
                                                begin: 0.96,
                                                end: 1.0,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOutCubic,
                                                ),
                                              ),
                                          child: child,
                                        ),
                                      );
                                    },
                              );
                            },
                          ),
                          const Divider(height: 1, color: Colors.black12),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: canSubmit
                                    ? () {
                                        Navigator.of(ctx).pop(
                                          ScheduleBookingResult(
                                            day: selectedDay,
                                            start: selectedTime,
                                            end: selectedEndTime,
                                          ),
                                        );
                                      }
                                    : null,
                                style: schedulePrimaryButtonStyle,
                                child: Text(
                                  canSubmit
                                      ? 'Book ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][selectedDay.weekday - 1]} ${selectedDay.day} ${monthNames[selectedDay.month - 1]} at ${timeLabel(selectedTime)}'
                                      : 'Book in advance',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

List<DateTimeRange> _parseBlockedDateRanges(dynamic raw) {
  if (raw is Iterable) {
    final ranges = <DateTimeRange>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final start = _parseAvailabilityDate(entry['start']);
        final end = _parseAvailabilityDate(entry['end']);
        if (start != null && end != null) {
          ranges.add(
            DateTimeRange(
              start: DateTime(start.year, start.month, start.day),
              end: DateTime(end.year, end.month, end.day),
            ),
          );
        }
      }
    }
    return ranges;
  }
  return const <DateTimeRange>[];
}

DateTime? _parseAvailabilityDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

Set<int> _parseUnavailableWeekdays(dynamic raw) {
  final result = <int>{};
  if (raw is Iterable) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);

      final dynamic availableRaw = map['available'];
      final bool? isAvailable = switch (availableRaw) {
        final bool v => v,
        final String v =>
          v.toLowerCase() == 'true'
              ? true
              : v.toLowerCase() == 'false'
              ? false
              : null,
        final num v => v != 0,
        _ => null,
      };

      final dayName = (map['day'] as String?)?.trim();
      if (dayName == null || dayName.isEmpty) continue;

      final weekday = _weekdayFromName(dayName);
      if (weekday != null && isAvailable == false) {
        result.add(weekday);
      }
    }
  }
  return result;
}

Map<int, _WeeklyTimeRange> _parseWeeklyTimeRanges(dynamic raw) {
  final result = <int, _WeeklyTimeRange>{};
  if (raw is Iterable) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);

      final dayName = (map['day'] as String?)?.trim();
      if (dayName == null || dayName.isEmpty) continue;
      final weekday = _weekdayFromName(dayName);
      if (weekday == null) continue;

      final dynamic availableRaw = map['available'];
      final bool? isAvailable = switch (availableRaw) {
        final bool v => v,
        final String v =>
          v.toLowerCase() == 'true'
              ? true
              : v.toLowerCase() == 'false'
              ? false
              : null,
        final num v => v != 0,
        _ => null,
      };
      if (isAvailable != true) continue;

      final startRaw = (map['start'] as String?)?.trim();
      final endRaw = (map['end'] as String?)?.trim();
      final start = _parseTimeOfDay(startRaw);
      final end = _parseTimeOfDay(endRaw);
      if (start == null || end == null) continue;

      result[weekday] = _WeeklyTimeRange(start: start, end: end);
    }
  }
  return result;
}

int? _weekdayFromName(String day) {
  final key = day.trim().toLowerCase();
  return switch (key) {
    'monday' || 'mon' => DateTime.monday,
    'tuesday' || 'tue' => DateTime.tuesday,
    'wednesday' || 'wed' => DateTime.wednesday,
    'thursday' || 'thu' => DateTime.thursday,
    'friday' || 'fri' => DateTime.friday,
    'saturday' || 'sat' => DateTime.saturday,
    'sunday' || 'sun' => DateTime.sunday,
    _ => null,
  };
}

TimeOfDay? _parseTimeOfDay(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

List<TimeOfDay> _generateTimeSlots({
  required TimeOfDay start,
  required TimeOfDay end,
  required int minuteInterval,
}) {
  final startMinutes = (start.hour * 60) + start.minute;
  final endMinutes = (end.hour * 60) + end.minute;
  if (minuteInterval <= 0 || endMinutes < startMinutes) {
    return const <TimeOfDay>[];
  }

  int first = startMinutes;
  if (first % minuteInterval != 0) {
    first = ((first ~/ minuteInterval) + 1) * minuteInterval;
  }
  int last = endMinutes;
  last = (last ~/ minuteInterval) * minuteInterval;
  if (last < first) return const <TimeOfDay>[];

  final slots = <TimeOfDay>[];
  for (int m = first; m <= last; m += minuteInterval) {
    slots.add(TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
  }
  return slots;
}
