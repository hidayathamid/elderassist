import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';

import 'firebase_options.dart';
import 'services/push_service.dart';
import 'widgets/auth_wrapper.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'screens/user/user_root_screen.dart';

/// =============================
/// BACKGROUND NOTIFICATION HANDLER
/// =============================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Global navigator key (used for push navigation)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const Color _actionGold = Color(0xFFF4B63D);
const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================
  // INITIALIZE FIREBASE
  // ========================================
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ========================================
  // ?? ACTIVATE APP CHECK (DEV MODE)
  // ========================================
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );
  final appCheckToken = await FirebaseAppCheck.instance.getToken(false);
  debugPrint('App Check token: $appCheckToken');

  // ========================================
  // ?? ENSURE USER IS AUTHENTICATED
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

class ElderAssistApp extends StatefulWidget {
  const ElderAssistApp({super.key});

  @override
  State<ElderAssistApp> createState() => _ElderAssistAppState();
}

class _ElderAssistAppState extends State<ElderAssistApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _linkSubscription;
  bool _handledPaymentLink = false;

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
    if (_handledPaymentLink) return;
    if (uri == null) return;
    if (uri.scheme == 'elderassist' && uri.host == 'payment-success') {
      _handledPaymentLink = true;
      _showPaymentSuccess();
    }
  }

  Future<void> _showPaymentSuccess() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Payment successful',
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: const Text(
          'Thank you! Your payment is complete and the booking status will be updated automatically.',
          textAlign: TextAlign.center,
          style: _dialogContentStyle,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const UserRootScreen(initialIndex: 3),
                  ),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _actionGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amber400 = Colors.amber[400]!;

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
