class CaregiverModel {
  final String caregiverId;
  final String name;
  final String phone;
  final String photoUrl;
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
      specialization: data['specialization'] ?? '',
      services: List<String>.from(data['services']),
      certifications: List<String>.from(data['certifications']),
      rating: (data['rating']).toDouble(),
      jobsCompleted: data['jobsCompleted'],
      availability: data['availability'],
      lat: (data['lat']).toDouble(),
      lng: (data['lng']).toDouble(),
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
      specialization: safeData['specialization'] as String? ?? '',
      services: _safeStringList(safeData['services']),
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
      "specialization": specialization,
      "services": services,
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

  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static int _safeInt(dynamic value, [int fallback = 0]) {
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  String get id => caregiverId;
}
