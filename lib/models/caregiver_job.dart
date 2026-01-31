import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/service_preferences.dart';

class CaregiverJob {
  const CaregiverJob({
    required this.bookingId,
    required this.userId,
    required this.personId,
    required this.addressId,
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
    this.startTime = '',
    this.endTime = '',
    this.personPhotoUrl = '',
    required this.personLabel,
    required this.personAddress,
    required this.cancellationReason,
  });

  final String bookingId;
  final String userId;
  final String personId;
  final String addressId;
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
  final String startTime;
  final String endTime;
  final String personPhotoUrl;
  final String personLabel;
  final String personAddress;
  final String cancellationReason;

  static CaregiverJob? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final hiddenLegacy = (data['hidden'] as bool?) == true;
    final hiddenForCaregiver = (data['hiddenForCaregiver'] as bool?) == true;
    if (hiddenLegacy || hiddenForCaregiver) return null;

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
      addressId:
          (data['addressId'] as String?) ??
          (data['selectedAddressId'] as String?) ??
          (data['addressID'] as String?) ??
          '',
      personName: (data['personName'] as String?) ?? 'Client',
      scheduledDate:
          (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'PENDING',
      price:
          (data['servicePrice'] as Object?)?.toString() ??
          (data['price'] as Object?)?.toString() ??
          'RM 0',
      notes:
          (data['personNotes'] as String?) ?? (data['notes'] as String?) ?? '',
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
      startTime: (data['startTime'] as String?) ?? '',
      endTime: (data['endTime'] as String?) ?? '',
      personPhotoUrl:
          (data['personPhotoUrl'] as String?) ??
          (data['personPhoto'] as String?) ??
          (data['personAvatarUrl'] as String?) ??
          (data['personImageUrl'] as String?) ??
          '',
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
      normalizedStatus == 'EMERGENCY_ALERT' ||
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
  final match = _findAddressEntry(data, job) ?? _primaryAddressMap(data);
  final rawLabel =
      _stringValue(match?['label']) ??
      _stringValue(match?['forWho']) ??
      _stringValue(data?['addressLabel']);
  return rawLabel?.trim().isNotEmpty == true ? rawLabel!.trim() : null;
}

String? resolvePersonName(Map<String, dynamic>? data, CaregiverJob job) {
  // Align with ActivityScreen's person selection:
  // prefer selected entry name, then user's main name, then booking snapshot.
  final match = _findAddressEntry(data, job) ?? _primaryAddressMap(data);
  final rawName =
      _stringValue(match?['name']) ??
      _stringValue(data?['name']) ??
      job.personName;
  final trimmed = rawName.trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

String? resolvePersonAddress(Map<String, dynamic>? data, CaregiverJob job) {
  // Align with ActivityScreen's person selection.
  final match = _findAddressEntry(data, job) ?? _primaryAddressMap(data);
  final raw =
      _stringValue(
        match?['address'] ??
            match?['addressLine'] ??
            match?['location'] ??
            match?['street'],
      ) ??
      job.personAddress;
  final trimmed = raw.trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

String? resolvePersonPhotoUrl(Map<String, dynamic>? data, CaregiverJob job) {
  // Align with ActivityScreen's person photo selection:
  // prefer selected entry photoUrl, then user's main photoUrl.
  final match = _findAddressEntry(data, job) ?? _primaryAddressMap(data);
  final raw =
      _stringValue(match?['photoUrl']) ??
      _stringValue(data?['photoUrl']) ??
      '';
  final trimmed = raw.trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

Map<String, dynamic>? _findAddressEntry(
  Map<String, dynamic>? data,
  CaregiverJob job,
) {
  final entries = _addressEntries(data);
  if (entries.isEmpty) return null;
  final jobBookingId = job.bookingId;
  final jobPersonId = job.personId;
  final jobAddressId = job.addressId;

  // Important: match only by explicit identifiers to avoid showing an incorrect
  // person photo/name (prefer missing over wrong).
  if (jobAddressId.trim().isNotEmpty) {
    final target = jobAddressId.trim();
    for (final entry in entries) {
      final entryId = _stringValue(entry['id']);
      if (entryId != null && entryId == target) return entry;
      final entryAddressId = _stringValue(entry['addressId']);
      if (entryAddressId != null && entryAddressId == target) return entry;
    }
  }

  if (jobPersonId.trim().isNotEmpty) {
    final target = jobPersonId.trim();
    for (final entry in entries) {
      final entryId = _stringValue(entry['id']);
      if (entryId != null && entryId == target) return entry;
      final entryPersonId = _stringValue(entry['personId']);
      if (entryPersonId != null && entryPersonId == target) return entry;
    }
  }

  if (jobBookingId.trim().isNotEmpty) {
    final target = jobBookingId.trim();
    for (final entry in entries) {
      final entryBookingId = _stringValue(entry['bookingId']);
      if (entryBookingId != null && entryBookingId == target) return entry;
    }
  }

  return null;
}

Map<String, dynamic>? _primaryAddressMap(Map<String, dynamic>? data) {
  final entries = _addressEntries(data);
  if (entries.isEmpty) return null;
  final defaultEntry = entries.firstWhere(
    (entry) => entry['isDefault'] == true,
    orElse: () => entries.first,
  );
  return defaultEntry;
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
