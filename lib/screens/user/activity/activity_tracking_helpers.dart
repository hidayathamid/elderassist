import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimelineEvent {
  const TimelineEvent({
    required this.title,
    this.description,
    this.timestamp,
    this.icon = Icons.circle,
    this.completed = false,
  });

  final String title;
  final String? description;
  final DateTime? timestamp;
  final IconData icon;
  final bool completed;
}

List<TimelineEvent> buildTimelineEvents(Map<String, dynamic> booking) {
  final events = <TimelineEvent>[];
  final raw =
      booking['tracking'] ?? booking['timeline'] ?? booking['trackingHistory'] ?? booking['updates'];
  if (raw is Iterable) {
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final label = normalizeString(entry['label']) ??
          normalizeString(entry['title']) ??
          normalizeString(entry['status']) ??
          'Update';
      final description = normalizeString(entry['description']) ??
          normalizeString(entry['detail']) ??
          normalizeString(entry['notes']);
      final timestamp = parseTimelineTimestamp(entry['timestamp'] ?? entry['time']);
      events.add(TimelineEvent(
        title: label,
        description: description,
        timestamp: timestamp,
        icon: Icons.check_circle_outlined,
        completed: true,
      ));
    }
  }

  if (events.isEmpty) {
    final createdAt = parseTimelineTimestamp(booking['createdAt']);
    final scheduled = mergeDateAndTime(
      normalizeString(booking['date']),
      normalizeString(booking['time']),
    );
    final caregiverName = normalizeString(booking['caregiverName']);
    events.add(TimelineEvent(
      title: 'Booking requested',
      description:
          'We received your request for ${normalizeString(booking['personName']) ?? 'your loved one'}.',
      timestamp: createdAt,
      icon: Icons.calendar_today,
      completed: true,
    ));
    if (caregiverName != null) {
      events.add(TimelineEvent(
        title: 'Caregiver assigned',
        description: caregiverName,
        timestamp: createdAt,
        icon: Icons.person_add,
        completed: true,
      ));
    }
    if (scheduled != null) {
      events.add(TimelineEvent(
        title: 'Care session scheduled',
        description: DateFormat('EEEE, d MMM h:mm a').format(scheduled),
        timestamp: scheduled,
        icon: Icons.schedule,
        completed: true,
      ));
    }
  } else {
    final status = (normalizeString(booking['status']) ?? '').toUpperCase();
    if (status == 'COMPLETED' &&
        events.every((event) => event.title.toUpperCase() != 'CARE SESSION COMPLETED')) {
      events.add(TimelineEvent(
        title: 'Care session completed',
        description: 'The session has been marked as completed.',
        timestamp: parseTimelineTimestamp(booking['completedAt']),
        icon: Icons.star_border,
        completed: true,
      ));
    }
  }

  events.sort((a, b) {
    final aValue = a.timestamp?.millisecondsSinceEpoch ?? 0;
    final bValue = b.timestamp?.millisecondsSinceEpoch ?? 0;
    return aValue.compareTo(bValue);
  });
  return events;
}

DateTime? parseTimelineTimestamp(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) {
    try {
      if (raw.contains('T')) {
        return DateTime.parse(raw);
      }
      return DateFormat('yyyy-MM-dd HH:mm:ss').parseLoose(raw);
    } catch (_) {
      try {
        return DateFormat('yyyy-MM-dd').parseLoose(raw);
      } catch (_) {}
    }
  }
  return null;
}

DateTime? mergeDateAndTime(String? date, String? time) {
  if (date == null || date.isEmpty) return null;
  try {
    final parsedDate = DateFormat('yyyy-MM-dd').parseLoose(date);
    if (time == null || time.isEmpty) return parsedDate;
    final parsedTime = DateFormat('HH:mm').parseLoose(time);
    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      parsedTime.hour,
      parsedTime.minute,
    );
  } catch (_) {
    return null;
  }
}

String formatTimelineTime(DateTime? time) {
  if (time == null) return '';
  return DateFormat('h:mm a').format(time);
}

String? normalizeString(dynamic value) {
  if (value == null) return null;
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is Iterable) {
    return value.whereType<String>().join(', ');
  }
  if (value is num) return value.toString();
  return value.toString();
}
