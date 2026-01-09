import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/touchdown_screen.dart';
import '../screens/caregiver/caregiver_root_screen.dart';
import '../screens/user/user_root_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  void _retry() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const TouchdownScreen();
        }

        final uid = snapshot.data!.uid;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection("users").doc(uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnap.hasError) {
              return _AuthLoadError(
                title: 'Unable to load account',
                message:
                    'You are signed in, but we can’t reach Firebase right now.\n\nCheck your internet/DNS, and if you enabled Firebase App Check enforcement make sure your debug token is allowlisted.',
                onRetry: _retry,
                onSignOut: FirebaseAuth.instance.signOut,
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

                if (cgSnap.hasError) {
                  return _AuthLoadError(
                    title: 'Unable to load account',
                    message:
                        'You are signed in, but we can’t reach Firebase right now.\n\nCheck your internet/DNS, and if you enabled Firebase App Check enforcement make sure your debug token is allowlisted.',
                    onRetry: _retry,
                    onSignOut: FirebaseAuth.instance.signOut,
                  );
                }

                if (cgSnap.data?.exists == true) {
                  return const CaregiverRootScreen();
                }

                if (cgSnap.hasData && cgSnap.data?.exists == false) {
                  FirebaseAuth.instance.signOut();
                }

                return const TouchdownScreen();
              },
            );
          },
        );
      },
    );
  }
}

class _AuthLoadError extends StatelessWidget {
  const _AuthLoadError({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await onSignOut();
                  },
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

