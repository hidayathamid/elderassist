import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'services/push_service.dart';
import 'widgets/auth_wrapper.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

/// =============================
/// BACKGROUND NOTIFICATION HANDLER
/// =============================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Global navigator key (used for push navigation)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================
  // INITIALIZE FIREBASE
  // ========================================
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ========================================
  // 🔐 ACTIVATE APP CHECK (DEV MODE)
  // ========================================
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );

  // ========================================
  // 🔥 ENSURE USER IS AUTHENTICATED
  // ========================================
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }

  // ========================================
  // FIREBASE CLOUD MESSAGING
  // ========================================
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ElderAssistApp());
}

class ElderAssistApp extends StatelessWidget {
  const ElderAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    final amber400 = Colors.amber[400]!;

    // ========================================
    // INIT PUSH NOTIFICATION SERVICE
    // ========================================
    PushService().init(navigatorKey);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ElderAssist App',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: amber400,
          brightness: Brightness.light,
        ),
      ),

      // ========================================
      // AUTH WRAPPER
      // At this point, user is GUARANTEED logged in
      // ========================================
      home: const AuthWrapper(),
    );
  }
}
