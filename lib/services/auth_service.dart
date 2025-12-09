import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/caregiver_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String get userId => _auth.currentUser?.uid ?? "";

  /// REGISTER
  Future<dynamic> registerUser({
    required String name,
    required String email,
    required String password,
    required String role, // user / caregiver
    required String phone,
    required List<Map<String, dynamic>> addresses,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      if (role == "user") {
        final user = UserModel(
          uid: uid,
          name: name,
          email: email,
          phone: phone,
          role: "user",
          address: addresses,
          createdAt: Timestamp.now(),
        );

        await _firestore.collection("users").doc(uid).set(user.toMap());
        return user;
      }

      /// CAREGIVER REGISTRATION (SAFE DEFAULT VALUES)
      final caregiver = CaregiverModel(
        caregiverId: uid,
        name: name,
        phone: phone,
        photoUrl: "",
        services: const [],
        certifications: const [],
        rating: 0.0,
        jobsCompleted: 0,
        availability: true,
        lat: 0.0,
        lng: 0.0,
      );

      await _firestore.collection("caregivers").doc(uid).set({
        ...caregiver.toMap(),
        "email": email,
        "role": "caregiver",
        "address": addresses,
        "created_at": FieldValue.serverTimestamp(),
      });

      return caregiver;
    } catch (_) {
      return null;
    }
  }

  /// LOGIN
  Future<dynamic> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      // Check USER
      final userDoc = await _firestore.collection("users").doc(uid).get();
      if (userDoc.exists) {
        return UserModel.fromMap(userDoc.data()!);
      }

      // Check CAREGIVER
      final cgDoc = await _firestore.collection("caregivers").doc(uid).get();
      if (cgDoc.exists) {
        return CaregiverModel.safeFromMap(uid, cgDoc.data());
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async => await _auth.signOut();
}
