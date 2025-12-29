import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
    String? defaultAddress,
    double? lat,
    double? lng,
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
          address: const [],
          createdAt: Timestamp.now(),
        );

        final userData = user.toMap();
        userData.remove('address');
        userData['defaultAddress'] = defaultAddress;
        if (lat != null) userData['lat'] = lat;
        if (lng != null) userData['lng'] = lng;
        await _firestore.collection("users").doc(uid).set(userData);
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

      final caregiverData = {
        ...caregiver.toMap(),
        "email": email,
        "role": "caregiver",
        "defaultAddress": defaultAddress,
        if (lat != null) "lat": lat,
        if (lng != null) "lng": lng,
        "created_at": FieldValue.serverTimestamp(),
      };
      caregiverData.remove('address');
      caregiverData.remove('certifications');
      caregiverData.remove('specialization');
      caregiverData.remove('services');
      caregiverData.remove('jobsCompleted');
      caregiverData.remove('price');
      await _firestore.collection("caregivers").doc(uid).set(caregiverData);

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
      debugPrint('loginUser: signed in uid=$uid');

      // Check CAREGIVER
      final cgDoc = await _firestore.collection("caregivers").doc(uid).get();
      debugPrint('loginUser: caregiverDoc.exists=${cgDoc.exists} uid=$uid');
      if (cgDoc.exists) {
        return CaregiverModel.safeFromMap(uid, cgDoc.data());
      }

      // Check USER
      final userDoc = await _firestore.collection("users").doc(uid).get();
      debugPrint('loginUser: userDoc.exists=${userDoc.exists} uid=$uid');
      if (userDoc.exists) {
        return UserModel.fromMap(userDoc.data()!);
      }
      debugPrint('loginUser: caregiverDoc.exists=${cgDoc.exists} uid=$uid');
      if (cgDoc.exists) {
        return CaregiverModel.safeFromMap(uid, cgDoc.data());
      }

      debugPrint('loginUser: no user or caregiver doc for uid=$uid');
      return null;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('loginUser: FirebaseAuthException ${e.message}');
      debugPrint(st.toString());
      return null;
    } catch (e, st) {
      debugPrint('loginUser: unexpected error $e');
      debugPrint(st.toString());
      return null;
    }
  }

  Future<void> signOut() async => await _auth.signOut();
}
