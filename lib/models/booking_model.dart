import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/service_preferences.dart';

class BookingModel {
  final String bookingId;
  final String userId;
  final String caregiverId;
  final String personId;
  final String personName;
  final String personAddress;
  final String service;
  final String date;
  final String scheduledDate;
  final String time;
  final String startTime;
  final String endTime;
  final double servicePrice;
  final String paymentMethod;
  final String status;
  final String notes;
  final Timestamp createdAt;

  BookingModel({
    required this.bookingId,
    required this.userId,
    required this.caregiverId,
    required this.personId,
    required this.personName,
    required this.personAddress,
    required this.service,
    required this.date,
    required this.scheduledDate,
    required this.time,
    required this.startTime,
    required this.endTime,
    required this.servicePrice,
    required this.paymentMethod,
    required this.status,
    required this.notes,
    required this.createdAt,
  });

  factory BookingModel.fromMap(String id, Map<String, dynamic> data) {
    final serviceLabel = extractServiceLabelFromFirestore(data);
    return BookingModel(
      bookingId: id,
      userId: data['userId'] as String? ?? '',
      caregiverId: data['caregiverId'] as String? ?? '',
      personId: data['personId'] as String? ?? '',
      personName: data['personName'] as String? ?? '',
      personAddress: data['personAddress'] as String? ?? '',
      service: serviceLabel,
      date: data['date'] as String? ?? '',
      scheduledDate: data['scheduledDate'] as String? ?? '',
      time: data['time'] as String? ?? '',
      startTime: data['startTime'] as String? ?? '',
      endTime: data['endTime'] as String? ?? '',
      servicePrice: (data['servicePrice'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] as String? ?? '',
      status: data['status'] as String? ?? '',
      notes: (data['personNotes'] as String?) ?? (data['notes'] as String?) ?? '',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "userId": userId,
      "caregiverId": caregiverId,
      "personId": personId,
      "personName": personName,
      "personAddress": personAddress,
      "servicePreferences": extractServicePreferencesList(service),
      "date": date,
      "scheduledDate": scheduledDate,
      "time": time,
      "startTime": startTime,
      "endTime": endTime,
      "servicePrice": servicePrice,
      "paymentMethod": paymentMethod,
      "status": status,
      "personNotes": notes,
      "createdAt": createdAt,
    };
  }
}
