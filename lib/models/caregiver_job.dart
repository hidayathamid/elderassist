import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/service_preferences.dart';

class CaregiverJob {
  const CaregiverJob({
    required this.bookingId,
    required this.userId,
    required this.personId,
    required this.personName,
    required this.scheduledDate,
    required this.status,
    required this.price,
    required this.notes,
    required this.caregiverId,
    required this.location,
    required this.service,
    required this.personAge,
    required this.time,
    required this.personLabel,
    required this.personAddress,
    required this.cancellationReason,
  });

  final String bookingId;
  final String userId;
  final String personId;
  final String personName;
  final String scheduledDate;
  final String status;
  final String price;
  final String notes;
  final String caregiverId;
  final String location;
  final String service;
  final String personAge;
  final String time;
  final String personLabel;
  final String personAddress;
  final String cancellationReason;

  static CaregiverJob? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if ((data['hidden'] as bool?) == true) return null;

    String parseAge() {
      final rawAge = data['personAge'] ?? data['age'];
      if (rawAge is num) {
        return rawAge.toInt().toString();
      }
      if (rawAge is String && rawAge.trim().isNotEmpty) {
        return rawAge.trim();
      }
      return '';
    }

    final serviceLabel = extractServiceLabelFromFirestore(data);

    return CaregiverJob(
      bookingId: doc.id,
      userId: (data['userId'] as String?) ?? '',
      personId: (data['personId'] as String?) ?? '',
      personName: (data['personName'] as String?) ?? 'Client',
      scheduledDate:
          (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'PENDING',
      price:
          (data['servicePrice'] as Object?)?.toString() ??
          (data['price'] as Object?)?.toString() ??
          'RM 0',
      notes: (data['notes'] as String?) ?? '',
      caregiverId:
          (data['caregiverId'] as String?) ??
          doc.reference.parent.parent?.id ??
          '',
      location:
          (data['address'] as String?) ??
          (data['personAddress'] as String?) ??
          '',
      service: serviceLabel.isNotEmpty ? serviceLabel : 'Home care',
      personAge: parseAge(),
      time: (data['time'] as String?) ?? '',
      personLabel: (data['personLabel'] as String?) ?? '',
      personAddress:
          (data['personAddress'] as String?) ??
          (data['address'] as String?) ??
          '',
      cancellationReason: (data['cancellationReason'] as String?) ?? '',
    );
  }

  String get normalizedStatus => status.trim().toUpperCase();

  bool get isActiveStatus =>
      normalizedStatus == 'ASSIGNED' ||
      normalizedStatus == 'ONGOING' ||
      normalizedStatus == 'IN_PROGRESS';

  bool get isScheduledStatus =>
      normalizedStatus == 'SCHEDULED' ||
      normalizedStatus == 'PENDING' ||
      normalizedStatus == 'READY';

  bool get isHistoryStatus {
    return normalizedStatus == 'COMPLETED' ||
        normalizedStatus == 'CANCELLED' ||
        normalizedStatus == 'CANCELED';
  }

  DateTime? get scheduledDateTime => _parseScheduledDate(scheduledDate);
}

String? resolvePersonLabel(Map<String, dynamic>? data, CaregiverJob job) {
  final match = _findAddressEntry(data, job);
  final rawLabel =
      _stringValue(match?['label']) ??
      _stringValue(match?['forWho']) ??
      _stringValue(data?['addressLabel']);
  return rawLabel?.trim().isNotEmpty == true ? rawLabel!.trim() : null;
}

Map<String, dynamic>? _findAddressEntry(
  Map<String, dynamic>? data,
  CaregiverJob job,
) {
  final entries = _addressEntries(data);
  if (entries.isEmpty) return null;
  final jobBookingId = job.bookingId;
  final jobPersonId = job.personId;
  for (final entry in entries) {
    final entryId = _stringValue(entry['id']);
    if (entryId != null &&
        (entryId == jobPersonId || entryId == jobBookingId)) {
      return entry;
    }
    final entryBookingId = _stringValue(entry['bookingId']);
    if (entryBookingId != null && entryBookingId == jobBookingId) {
      return entry;
    }
  }
  return null;
}

List<Map<String, dynamic>> _addressEntries(Map<String, dynamic>? data) {
  if (data == null) return [];
  final raw = data['address'] ?? data['addresses'] ?? data['addressList'];
  return _extractAddressList(raw);
}

List<Map<String, dynamic>> _extractAddressList(dynamic raw) {
  if (raw is Map) {
    return [Map<String, dynamic>.from(raw)];
  }
  if (raw is Iterable) {
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  return [];
}

String? _stringValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is Iterable) {
    final joinable = value.whereType<String>().toList();
    if (joinable.isNotEmpty) {
      return joinable.join(', ');
    }
  }
  if (value != null) return value.toString();
  return null;
}

DateTime? _parseScheduledDate(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final trimmed = input.trim();
  try {
    return DateTime.parse(trimmed);
  } catch (_) {}
  final formats = [
    DateFormat('yyyy-MM-dd'),
    DateFormat('dd MMM yyyy'),
    DateFormat('MMM d, yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('yyyy/MM/dd'),
  ];
  for (final format in formats) {
    try {
      return format.parseStrict(trimmed);
    } catch (_) {
      continue;
    }
  }
  return null;
}
