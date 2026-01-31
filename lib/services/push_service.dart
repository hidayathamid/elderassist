import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/caregiver/sos/caregiver_sos_root_screen.dart';
import '../screens/user/chat/user_chat_screen.dart';
import '../screens/user/sos/sos_activate_screen.dart';

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'elderassist_high_importance',
    'ElderAssist Notifications',
    description: 'Important updates (SOS, chat, bookings).',
    importance: Importance.high,
  );

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;

    await _initLocalNotifications(navigatorKey);

    // iOS permission + allow alerts while app is open.
    if (Platform.isIOS) {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      // Android 13+ runtime notification permission (best-effort).
      try {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (_) {}
    }

    // get and save token if signed in
    await _updateToken();
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await _updateToken();
      }
    });

    // foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('FCM onMessage: ${message.data}');
      }
      _showForegroundNotification(message);
    });

    // app opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNavigation(message.data, navigatorKey);
    });

    // handle terminated state
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      _handleNavigation(initial.data, navigatorKey);
    }
  }

  Future<void> _initLocalNotifications(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _local.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _handleNavigation(
              decoded.map((k, v) => MapEntry(k.toString(), v)),
              navigatorKey,
            );
          }
        } catch (_) {}
      },
    );

    if (!Platform.isAndroid) return;
    try {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    } catch (_) {}
  }

  Future<void> _updateToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await _fm.getToken();
      if (token != null) {
        await _saveToken(user.uid, token);
      }

      // Topic subscription enables server-side targeting without storing tokens.
      try {
        await _fm.subscribeToTopic(user.uid);
      } catch (_) {}

      // token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null || currentUid.isEmpty) return;
        await _saveToken(currentUid, t);
        try {
          await _fm.subscribeToTopic(currentUid);
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _saveToken(String uid, String token) async {
    final firestore = FirebaseFirestore.instance;
    final adminRef = firestore.collection('admin').doc(uid);
    final adminSnap = await adminRef.get();
    if (adminSnap.exists) {
      await adminRef.set({'fcmToken': token}, SetOptions(merge: true));
      return;
    }
    final caregiverRef = firestore.collection('caregivers').doc(uid);
    final caregiverSnap = await caregiverRef.get();
    if (caregiverSnap.exists) {
      await caregiverRef.set({'fcmToken': token}, SetOptions(merge: true));
      return;
    }
    final userRef = firestore.collection('users').doc(uid);
    final userSnap = await userRef.get();
    if (userSnap.exists) {
      await userRef.set({'fcmToken': token}, SetOptions(merge: true));
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final title = message.notification?.title?.trim().isNotEmpty == true
          ? message.notification!.title!.trim()
          : 'ElderAssist';
      final body = message.notification?.body?.trim().isNotEmpty == true
          ? message.notification!.body!.trim()
          : (message.data['body']?.toString().trim().isNotEmpty == true
              ? message.data['body']!.toString().trim()
              : null);
      if (body == null) return;

      final payload = message.data.isEmpty ? null : jsonEncode(message.data);
      final android = AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const ios = DarwinNotificationDetails();

      await _local.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        NotificationDetails(android: android, iOS: ios),
        payload: payload,
      );
    } catch (_) {}
  }

  void _handleNavigation(
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navKey,
  ) {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'sos_activated' || type == 'sos_status') {
      navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const SosActivateScreen()),
      );
      return;
    }
    if (type == 'sos_offer') {
      navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const CaregiverSosRootScreen()),
      );
      return;
    }

    final chatId = (data['chatId'] ?? '').toString().trim();
    final otherId = (data['otherUserId'] ?? '').toString().trim();
    final otherName = (data['otherUserName'] ?? '').toString().trim();
    if (chatId.isNotEmpty && otherId.isNotEmpty && otherName.isNotEmpty) {
      final bookingId = (data['bookingId'] ?? '').toString().trim();
      navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => UserChatScreen(
            chatId: chatId,
            otherUserId: otherId,
            otherUserName: otherName,
            hideCallAction: bookingId.isNotEmpty,
          ),
        ),
      );
    }
  }
}
