import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/user/user_root_screen.dart';
import '../screens/caregiver/caregiver_root_screen.dart';
import '../screens/auth/touchdown_screen.dart'; // 👉 tambah import ni (ikut path sebenar kau)

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 🔥 User belum login → pergi TouchdownScreen (onboarding + login/register)
        if (!snapshot.hasData) {
          return const TouchdownScreen();
        }

        final uid = snapshot.data!.uid;

        // 🔥 Dah login → check role dalam Firestore
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection("users").doc(uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnap.data?.exists == true) {
              return const UserRootScreen();
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection("caregivers")
                  .doc(uid)
                  .get(),
              builder: (context, cgSnap) {
                if (cgSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (cgSnap.data?.exists == true) {
                  return const CaregiverRootScreen();
                }

                // Kalau betul-betul tak jumpa apa-apa document role → force logout
                FirebaseAuth.instance.signOut();
                return const TouchdownScreen();
              },
            );
          },
        );
      },
    );
  }
}
