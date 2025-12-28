import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final List<Map<String, dynamic>> address;
  final String? defaultAddress;
  final Timestamp? createdAt;
  final String? photoUrl;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.address,
    this.defaultAddress,
    this.createdAt,
    this.photoUrl,
  });

  factory UserModel.fromMap(Map<String, dynamic> data) {
      final rawAddress = data['defaultAddress'];
      return UserModel(
        uid: data["uid"],
        name: data["name"] ?? "",
        email: data["email"] ?? "",
        phone: data["phone"] ?? "",
        role: data["role"] ?? "user",
        address: List<Map<String, dynamic>>.from(data["address"] ?? []),
      defaultAddress: rawAddress as String?,
        createdAt: data["created_at"],
        photoUrl: data["photoUrl"],
      );
  }

  Map<String, dynamic> toMap() {
    return {
      "uid": uid,
      "name": name,
      "email": email,
      "phone": phone,
      "role": role,
      "address": address,
      "defaultAddress": defaultAddress,
      "created_at": createdAt,
      "photoUrl": photoUrl,
    };
  }
}
