import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';

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

Future<void> _initFirebaseAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kReleaseMode
          ? AndroidProvider.playIntegrity
          : AndroidProvider.debug,
    );
  } catch (err) {
    debugPrint('Firebase App Check activate failed: $err');
    return;
  }

  if (!kDebugMode) return;
  try {
    final appCheckToken = await FirebaseAppCheck.instance.getToken(false);
    debugPrint('App Check token: $appCheckToken');
  } catch (err) {
    debugPrint('App Check token fetch failed: $err');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================
  // INITIALIZE FIREBASE
  // ========================================
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ========================================
  // ?? ACTIVATE APP CHECK (DEV MODE)
  // ========================================
  await _initFirebaseAppCheck();

  // ========================================
  // ?? ENSURE USER IS AUTHENTICATED
  // ========================================
  final auth = FirebaseAuth.instance;
  // On app start / hot restart FirebaseAuth may take a moment to restore the
  // persisted session. Avoid signing in anonymously too early (which would
  // replace an existing caregiver/user session).
  User? initialUser;
  try {
    initialUser = await auth.authStateChanges().first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => auth.currentUser,
    );
  } catch (_) {
    initialUser = auth.currentUser;
  }
  if (initialUser == null) {
    try {
      await auth.signInAnonymously();
    } on FirebaseAuthException catch (err) {
      debugPrint(
        'Anonymous sign-in failed (${err.code}): ${err.message ?? err}',
      );
    } catch (err) {
      debugPrint('Anonymous sign-in failed: $err');
    }
  }

  // ========================================
  // FIREBASE CLOUD MESSAGING
  // ========================================
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ElderAssistApp());
}

class ElderAssistApp extends StatefulWidget {
  const ElderAssistApp({super.key});

  @override
  State<ElderAssistApp> createState() => _ElderAssistAppState();
}

class _ElderAssistAppState extends State<ElderAssistApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    PushService().init(navigatorKey);
    _initDeepLinkListener();
  }

  Future<void> _initDeepLinkListener() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      _handleDeepLink(initialUri);
    } catch (err) {
      debugPrint('Failed to capture initial deep link: $err');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (err) => debugPrint('Deep link stream error: $err'),
    );
  }

  void _handleDeepLink(Uri? uri) {
    if (uri == null) return;
    // Payment success/failure dialogs are handled inside BookingSummaryScreen
    // after verifying the payment status (avoids false positives on cancel).
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amber400 = const Color.fromARGB(255, 0, 0, 0);

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
