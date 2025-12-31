import 'package:cloud_firestore/cloud_firestore.dart';

class CaregiverModel {
  final String caregiverId;
  final String name;
  final String phone;
  final String photoUrl;
  final String bio;
  final String defaultAddress;
  final DateTime? lastSeenJobsAt;
  final String specialization;
  final List<String> services;
  final List<String> certifications;
  final double rating;
  final int jobsCompleted;
  final bool availability;
  final double lat;
  final double lng;
  final dynamic price;

  CaregiverModel({
    required this.caregiverId,
    required this.name,
    required this.phone,
    required this.photoUrl,
    this.bio = '',
    this.defaultAddress = '',
    this.lastSeenJobsAt,
    this.specialization = '',
    required this.services,
    required this.certifications,
    required this.rating,
    required this.jobsCompleted,
    required this.availability,
    required this.lat,
    required this.lng,
    this.price,
  });

  factory CaregiverModel.fromMap(String id, Map<String, dynamic> data) {
    return CaregiverModel(
      caregiverId: id,
      name: data['name'],
      phone: data['phone'],
      photoUrl: data['photoUrl'],
      bio: data['bio'] as String? ?? '',
      defaultAddress: data['defaultAddress'] as String? ?? '',
      lastSeenJobsAt: _dateTimeFromFirestore(data['lastSeenJobsAt']),
      specialization: data['specialization'] ?? '',
      services: _safeStringList(
        data['servicePreferences'] ?? data['services'],
      ),
      certifications: _safeStringList(data['certifications']),
      rating: (data['rating']).toDouble(),
      jobsCompleted: _safeInt(data['jobsCompleted']),
      availability: data['availability'],
      lat: _latFromData(data),
      lng: _lngFromData(data),
      price: data['price'],
    );
  }

  static CaregiverModel safeFromMap(String id, Map<String, dynamic>? data) {
    final safeData = data ?? <String, dynamic>{};
    return CaregiverModel(
      caregiverId: id,
      name: safeData['name'] as String? ?? '',
      phone: safeData['phone'] as String? ?? '',
      photoUrl: safeData['photoUrl'] as String? ?? '',
      bio: safeData['bio'] as String? ?? '',
      defaultAddress: safeData['defaultAddress'] as String? ?? '',
      lastSeenJobsAt: _dateTimeFromFirestore(safeData['lastSeenJobsAt']),
      specialization: safeData['specialization'] as String? ?? '',
      services: _safeStringList(
        safeData['servicePreferences'] ?? safeData['services'],
      ),
      certifications: _safeStringList(safeData['certifications']),
      rating: _safeDouble(safeData['rating']),
      jobsCompleted: _safeInt(safeData['jobsCompleted']),
      availability: safeData['availability'] as bool? ?? false,
      lat: _safeDouble(safeData['lat']),
      lng: _safeDouble(safeData['lng']),
      price: safeData['price'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "phone": phone,
      "photoUrl": photoUrl,
      "bio": bio,
      "defaultAddress": defaultAddress,
      "lastSeenJobsAt": lastSeenJobsAt,
      "specialization": specialization,
      "servicePreferences": services,
      "certifications": certifications,
      "rating": rating,
      "jobsCompleted": jobsCompleted,
      "availability": availability,
      "lat": lat,
      "lng": lng,
      "price": price,
    };
  }

  static List<String> _safeStringList(dynamic value) {
    if (value is Iterable) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  static DateTime? _dateTimeFromFirestore(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static double _latFromData(Map<String, dynamic> data) {
    final lat = data['lat'];
    if (lat is num) return lat.toDouble();
    final addressLat = _addressCoordinate(data, 'latitude') ?? _addressCoordinate(data, 'lat');
    return addressLat ?? 0.0;
  }

  static double _lngFromData(Map<String, dynamic> data) {
    final lng = data['lng'];
    if (lng is num) return lng.toDouble();
    final addressLng = _addressCoordinate(data, 'longitude') ?? _addressCoordinate(data, 'lng');
    return addressLng ?? 0.0;
  }

  static double? _addressCoordinate(
    Map<String, dynamic> data,
    String key,
  ) {
    final rawAddresses = data['address'];
    if (rawAddresses is Iterable) {
      for (final entry in rawAddresses) {
        if (entry is Map<String, dynamic>) {
          final value = entry[key];
          if (value is num) return value.toDouble();
          if (value is String) {
            final parsed = double.tryParse(value);
            if (parsed != null) return parsed;
          }
        }
      }
    }
    return null;
  }

  static int _safeInt(dynamic value, [int fallback = 0]) {
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  String get id => caregiverId;
}
