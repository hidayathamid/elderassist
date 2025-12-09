import 'package:cloud_firestore/cloud_firestore.dart';

class SOSModel {
  final String sosId;
  final String userId;
  final String userName;
  final String userPhone;
  final double userLat;
  final double userLng;
  final String status;
  final Timestamp requestedAt;

  SOSModel({
    required this.sosId,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.userLat,
    required this.userLng,
    required this.status,
    required this.requestedAt,
  });

  factory SOSModel.fromMap(String id, Map<String, dynamic> data) {
    return SOSModel(
      sosId: id,
      userId: data['userId'],
      userName: data['userName'],
      userPhone: data['userPhone'],
      userLat: (data['userLat']).toDouble(),
      userLng: (data['userLng']).toDouble(),
      status: data['status'],
      requestedAt: data['requestedAt'],
    );
  }
}
