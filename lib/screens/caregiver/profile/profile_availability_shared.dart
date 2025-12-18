import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../ui_tokens.dart';

final DateFormat blockedStartFormat = DateFormat('MMM d');
final DateFormat blockedFullFormat = DateFormat('MMM d, yyyy');

const Color availabilityTealAccent = Color(0xFF00A8A7);
const Color availabilityDarkText = Color(0xFF1B1D29);

const TextStyle availabilityAppBarTitleStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 18,
  fontWeight: FontWeight.w600,
);
const TextStyle availabilitySectionHeaderStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 15,
  fontWeight: FontWeight.w700,
);
const TextStyle availabilityBodyTextStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);
const TextStyle availabilityBodySemiBoldTextStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 14,
  fontWeight: FontWeight.w600,
);
const TextStyle availabilityBodyBoldTextStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 16,
  fontWeight: FontWeight.w700,
);
const TextStyle availabilitySmallTextStyle = TextStyle(
  color: availabilityDarkText,
  fontSize: 12,
);
final TextStyle availabilityHelperLabelStyle = TextStyle(
  color: availabilityDarkText.withValues(alpha: 0.6),
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

Color mutedAvailabilityTextColor() =>
    availabilityDarkText.withValues(alpha: 0.55);

List<BoxShadow> availabilityPrimaryCardShadow() {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

List<BoxShadow> availabilitySecondaryCardShadow() {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
}

ThemeData availabilityPickerTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: availabilityTealAccent,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: availabilityDarkText,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.r18),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: UiTokens.s12,
        vertical: UiTokens.s6,
      ),
      titleTextStyle: const TextStyle(
        fontSize: UiTokens.fs16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
      contentTextStyle: const TextStyle(
        fontSize: UiTokens.fs12,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.r18),
      ),
      dialHandColor: availabilityTealAccent,
      dialBackgroundColor: Colors.white,
      entryModeIconColor: availabilityTealAccent,
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.r12),
      ),
      hourMinuteColor: Colors.grey.shade200,
      hourMinuteTextColor: availabilityDarkText,
      dayPeriodTextColor: availabilityDarkText,
      dayPeriodColor: availabilityTealAccent,
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.r12),
      ),
      helpTextStyle: TextStyle(
        color: availabilityDarkText.withValues(alpha: 0.7),
        fontWeight: FontWeight.w600,
        fontSize: UiTokens.fs12,
      ),
      hourMinuteTextStyle: const TextStyle(
        fontSize: UiTokens.fs14,
        fontWeight: FontWeight.w600,
      ),
      dayPeriodTextStyle: const TextStyle(
        fontSize: UiTokens.fs12,
        fontWeight: FontWeight.w600,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.r18),
      ),
      headerHeadlineStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
      headerHelpStyle: TextStyle(
        color: availabilityDarkText.withValues(alpha: 0.7),
        fontWeight: FontWeight.w600,
      ),
      dayStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: availabilityTealAccent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

Widget availabilityPickerBuilder(BuildContext context, Widget? child) {
  return Theme(
    data: availabilityPickerTheme(context),
    child: child ?? const SizedBox.shrink(),
  );
}

class TimePickerChip extends StatelessWidget {
  const TimePickerChip({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.labelStyle,
    this.valueStyle,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s8,
          vertical: UiTokens.s2,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(UiTokens.r12),
        ),
        constraints: const BoxConstraints(minHeight: UiTokens.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle ?? availabilityHelperLabelStyle),
            const SizedBox(height: UiTokens.s4),
            Text(
              value.isEmpty ? 'Select time' : value,
              style: valueStyle ?? availabilityBodySemiBoldTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}

const List<DaySchedule> defaultWeeklySchedule = [
  DaySchedule(day: 'Monday', available: true, start: '08:00', end: '18:00'),
  DaySchedule(day: 'Tuesday', available: true, start: '08:00', end: '18:00'),
  DaySchedule(day: 'Wednesday', available: true, start: '08:00', end: '18:00'),
  DaySchedule(day: 'Thursday', available: true, start: '08:00', end: '18:00'),
  DaySchedule(day: 'Friday', available: true, start: '08:00', end: '16:00'),
  DaySchedule(day: 'Saturday', available: true, start: '09:00', end: '14:00'),
  DaySchedule(day: 'Sunday', available: false, start: '', end: ''),
];

final Map<String, DaySchedule> defaultScheduleLookup = Map.fromEntries(
  defaultWeeklySchedule.map((entry) => MapEntry(entry.day, entry)),
);

class DaySchedule {
  final String day;
  final bool available;
  final String start;
  final String end;

  const DaySchedule({
    required this.day,
    required this.available,
    required this.start,
    required this.end,
  });

  String get rangeLabel => '$start - $end';

  DaySchedule copyWith({bool? available, String? start, String? end}) {
    return DaySchedule(
      day: day,
      available: available ?? this.available,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      'available': available,
      if (start.isNotEmpty) 'start': start,
      if (end.isNotEmpty) 'end': end,
    };
  }
}

class BlockedDate {
  final DateTime? start;
  final DateTime? end;
  final String description;
  final String? fallbackLabel;

  const BlockedDate({
    this.start,
    this.end,
    required this.description,
    this.fallbackLabel,
  });

  String get displayLabel {
    if (start != null && end != null) {
      final startLabel = blockedStartFormat.format(start!);
      final endLabel = blockedFullFormat.format(end!);
      return '$startLabel - $endLabel';
    }
    return fallbackLabel ?? 'Blocked';
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'description': description,
      'label': displayLabel,
    };
    if (start != null) {
      map['start'] = start!.toIso8601String();
    }
    if (end != null) {
      map['end'] = end!.toIso8601String();
    }
    return map;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BlockedDate &&
        other.start == start &&
        other.end == end &&
        other.description == description &&
        other.fallbackLabel == fallbackLabel;
  }

  @override
  int get hashCode => Object.hash(start, end, description, fallbackLabel);
}
