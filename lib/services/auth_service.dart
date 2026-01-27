import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/caregiver_model.dart';
import '../models/admin_model.dart';

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
  Future<LoginResult> loginUser({
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

      try {
        // Check ADMIN
        final adminDoc = await _firestore.collection("admin").doc(uid).get();
        debugPrint('loginUser: adminDoc.exists=${adminDoc.exists} uid=$uid');
        if (adminDoc.exists) {
          return LoginResult.success(
            AdminModel.safeFromMap(uid, adminDoc.data()),
          );
        }

        final effectiveEmail = (cred.user?.email ?? email).trim();
        if (effectiveEmail.isNotEmpty) {
          final candidates = <String>{
            effectiveEmail,
            effectiveEmail.toLowerCase(),
          }.where((e) => e.trim().isNotEmpty).toList();

          for (final candidate in candidates) {
            final adminQuery = await _firestore
                .collection("admin")
                .where("email", isEqualTo: candidate)
                .limit(1)
                .get();
            if (adminQuery.docs.isEmpty) continue;

            final doc = adminQuery.docs.first;
            final data = doc.data();
            // Try to "link" to uid for future lookups (safe no-op if rules deny).
            try {
              await _firestore.collection("admin").doc(uid).set(
                {
                  ...data,
                  "email": candidate,
                  "role": (data["role"] as String?) ?? "admin",
                  "linkedFrom": doc.id,
                },
                SetOptions(merge: true),
              );
            } catch (e) {
              debugPrint('loginUser: admin link-to-uid failed: $e');
            }

            return LoginResult.success(AdminModel.safeFromMap(uid, data));
          }
        }

        // Check CAREGIVER (must come before user, since caregiver applicants are
        // also stored in `users` and can otherwise be routed to the wrong role).
        final cgDoc = await _firestore.collection("caregivers").doc(uid).get();
        debugPrint('loginUser: caregiverDoc.exists=${cgDoc.exists} uid=$uid');
        if (cgDoc.exists) {
          return LoginResult.success(CaregiverModel.safeFromMap(uid, cgDoc.data()));
        }

        // Check USER
        final userDoc = await _firestore.collection("users").doc(uid).get();
        debugPrint('loginUser: userDoc.exists=${userDoc.exists} uid=$uid');
        if (userDoc.exists) {
          return LoginResult.success(UserModel.fromMap(userDoc.data()!));
        }
      } catch (e, st) {
        debugPrint('loginUser: role lookup failed after sign-in: $e');
        debugPrint(st.toString());
        return LoginResult.signedInButRoleUnknown(
          errorCode: 'role-lookup-failed',
          errorMessage: e.toString(),
        );
      }

      debugPrint('loginUser: no admin/user/caregiver doc for uid=$uid');
      return const LoginResult.signedInButRoleUnknown(errorCode: 'no-role');
    } on FirebaseAuthException catch (e, st) {
      debugPrint('loginUser: FirebaseAuthException code=${e.code} message=${e.message}');
      debugPrint(st.toString());
      return LoginResult.failure(errorCode: e.code, errorMessage: e.message);
    } catch (e, st) {
      debugPrint('loginUser: unexpected error $e');
      debugPrint(st.toString());
      return LoginResult.failure(errorCode: 'unknown', errorMessage: e.toString());
    }
  }

  Future<void> signOut() async => await _auth.signOut();
}

class LoginResult {
  const LoginResult._({
    required this.signedIn,
    required this.profile,
    this.errorCode,
    this.errorMessage,
  });

  final bool signedIn;
  final dynamic profile;
  final String? errorCode;
  final String? errorMessage;

  bool get hasProfile => profile != null;

  factory LoginResult.success(dynamic profile) => LoginResult._(
        signedIn: true,
        profile: profile,
      );

  const factory LoginResult.signedInButRoleUnknown({
    String? errorCode,
    String? errorMessage,
  }) = _LoginSignedInButRoleUnknown;

  factory LoginResult.failure({
    required String errorCode,
    String? errorMessage,
  }) =>
      LoginResult._(
        signedIn: false,
        profile: null,
        errorCode: errorCode,
        errorMessage: errorMessage,
      );
}

class _LoginSignedInButRoleUnknown extends LoginResult {
  const _LoginSignedInButRoleUnknown({
    super.errorCode,
    super.errorMessage,
  }) : super._(signedIn: true, profile: null);
}
