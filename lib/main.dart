import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'services/push_service.dart';
import 'widgets/auth_wrapper.dart';

/// =============================
/// BACKGROUND NOTIFICATION HANDLER
/// =============================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================
  // Firebase App Check DISABLED for this build
  // Using Auth token only (no app attestation)
  // ========================================

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ElderAssistApp());
}

class ElderAssistApp extends StatelessWidget {
  const ElderAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    final amber400 = Colors.amber[400]!;

    // Initialize FCM push notifications
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
      home: const AuthWrapper(),
    );
  }
}
