import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_notice.dart';
import '../services/post_login_action.dart';
import '../screens/auth/touchdown_screen.dart';
import '../screens/admin/admin_root_screen.dart';
import '../screens/caregiver/caregiver_root_screen.dart';
import '../screens/user/user_root_screen.dart';
import '../screens/user/profile/profile_email_edit_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  void _retry() => setState(() {});

  Future<({bool adminExists, bool caregiverExists, bool userExists})>
  _resolveAccountType({
    required FirebaseFirestore db,
    required String uid,
    required String email,
  }) async {
    final futures = await Future.wait([
      db.collection("admin").doc(uid).get(),
      db.collection("caregivers").doc(uid).get(),
      db.collection("users").doc(uid).get(),
    ]);

    final adminSnap = futures[0] as DocumentSnapshot;
    final caregiverSnap = futures[1] as DocumentSnapshot;
    final userSnap = futures[2] as DocumentSnapshot;

    var adminExists = adminSnap.exists;
    if (!adminExists && email.trim().isNotEmpty) {
      final candidates = <String>{
        email.trim(),
        email.trim().toLowerCase(),
      }.where((e) => e.isNotEmpty).toList();

      for (final candidate in candidates) {
        final query = await db
            .collection("admin")
            .where("email", isEqualTo: candidate)
            .limit(1)
            .get();
        if (query.docs.isEmpty) continue;
        adminExists = true;

        // Best-effort: link to `admin/$uid` for future lookups.
        final doc = query.docs.first;
        try {
          await db.collection("admin").doc(uid).set({
            ...doc.data(),
            "email": candidate,
            "role": (doc.data()["role"] as String?) ?? "admin",
            "linkedFrom": doc.id,
          }, SetOptions(merge: true));
        } catch (_) {}
        break;
      }
    }

    return (
      adminExists: adminExists,
      caregiverExists: caregiverSnap.exists,
      userExists: userSnap.exists,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const TouchdownScreen();
        }

        final user = snapshot.data!;
        final uid = user.uid;
        final email = (user.email ?? '').trim();

        final db = FirebaseFirestore.instance;
        return FutureBuilder<
          ({bool adminExists, bool caregiverExists, bool userExists})
        >(
          future: _resolveAccountType(db: db, uid: uid, email: email),
          builder: (context, accountSnap) {
            if (accountSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (accountSnap.hasError) {
              return _AuthLoadError(
                title: 'Unable to load account',
                message:
                    'You are signed in, but we can’t reach Firebase right now.\n\nCheck your internet/DNS, and if you enabled Firebase App Check enforcement make sure your debug token is allowlisted.',
                onRetry: _retry,
                onSignOut: FirebaseAuth.instance.signOut,
              );
            }

            final adminExists = accountSnap.data?.adminExists == true;
            final caregiverExists = accountSnap.data?.caregiverExists == true;
            final userExists = accountSnap.data?.userExists == true;

            if (adminExists) {
              PostLoginAction.take();
              return const AdminRootScreen();
            }
            if (caregiverExists) {
              return _PostLoginActionGate(
                isCaregiver: true,
                child: _ForceLogoutGate(
                  uid: uid,
                  child: const CaregiverRootScreen(),
                ),
              );
            }
            if (userExists) {
              return _PostLoginActionGate(
                isCaregiver: false,
                child: _ForceLogoutGate(
                  uid: uid,
                  child: const UserRootScreen(),
                ),
              );
            }

            PostLoginAction.take();
            FirebaseAuth.instance.signOut();
            return const TouchdownScreen();
          },
        );
      },
    );
  }
}

class _PostLoginActionGate extends StatefulWidget {
  const _PostLoginActionGate({required this.isCaregiver, required this.child});

  final bool isCaregiver;
  final Widget child;

  @override
  State<_PostLoginActionGate> createState() => _PostLoginActionGateState();
}

class _PostLoginActionGateState extends State<_PostLoginActionGate> {
  bool _didRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _didRun) return;
      _didRun = true;
      final action = PostLoginAction.take();
      if (action == null) return;
      if (action.type != PostLoginActionType.openEmailEdit) return;
      final initialEmail = (FirebaseAuth.instance.currentUser?.email ?? '')
          .trim();
      if (initialEmail.isEmpty) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileEmailEditScreen(
            initialEmail: initialEmail,
            isCaregiver: widget.isCaregiver,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ForceLogoutGate extends StatefulWidget {
  const _ForceLogoutGate({required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  State<_ForceLogoutGate> createState() => _ForceLogoutGateState();
}

class _ForceLogoutGateState extends State<_ForceLogoutGate> {
  Timestamp? _lastSeen;
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid.trim();
    if (uid.isEmpty) return widget.child;

    final signedInAt =
        FirebaseAuth.instance.currentUser?.metadata.lastSignInTime;
    final db = FirebaseFirestore.instance;
    final caregiverRef = db.collection('caregivers').doc(uid);
    final userRef = db.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef.snapshots(),
      builder: (context, caregiverSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, userSnap) {
            final caregiverTs =
                caregiverSnap.data?.data()?['forceLogoutAt'] as Timestamp?;
            final userTs =
                userSnap.data?.data()?['forceLogoutAt'] as Timestamp?;
            final ts = () {
              if (caregiverTs == null) return userTs;
              if (userTs == null) return caregiverTs;
              return caregiverTs.compareTo(userTs) >= 0 ? caregiverTs : userTs;
            }();
            if (!_signingOut && ts != null) {
              final tsDate = ts.toDate();
              final alreadyRelogged =
                  signedInAt != null && !signedInAt.isBefore(tsDate);
              if (alreadyRelogged) {
                return widget.child;
              }
              final shouldLogout =
                  _lastSeen == null || ts.compareTo(_lastSeen!) > 0;
              if (shouldLogout) {
                _lastSeen = ts;
                _signingOut = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    AuthNotice.set(
                      'Successfully verified as caregiver. Please log in again as caregiver.',
                    );
                    await FirebaseAuth.instance.signOut();
                  } finally {
                    _signingOut = false;
                  }
                });
              }
            }
            return widget.child;
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
