import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/caregiver/sos/caregiver_sos_root_screen.dart';
import '../screens/user/chat/user_chat_screen.dart';
import '../screens/user/sos/sos_activate_screen.dart';

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  // Role-based FCM topics to avoid cross-role notifications on the same device.
  // Backend sends to: user_<uid>, caregiver_<uid>, admin_<uid>.
  static const String _roleUser = 'user';
  static const String _roleCaregiver = 'caregiver';
  static const String _roleAdmin = 'admin';

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentTopic;
  String _activeRole = _roleUser;
  bool _updatingToken = false;
  static const String _tokenResetMarkerFile = '.fcm_token_reset_v1';

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

    if (Platform.isIOS) {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      try {
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } catch (_) {}
    }

    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        await _handleSignedOut();
        return;
      }
      await _ensureTokenAndTopic(user.uid);
    });
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      await _ensureTokenAndTopic(current.uid);
    }

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
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_androidChannel);
    } catch (_) {}
  }

  Future<void> _updateToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _ensureTokenAndTopic(user.uid);
    } catch (_) {}
  }

  void setActiveRole(String role) {
    final normalized = role.trim().toLowerCase();
    final next =
        normalized == _roleAdmin || normalized == _roleCaregiver || normalized == _roleUser
        ? normalized
        : _roleUser;
    if (_activeRole == next) return;
    _activeRole = next;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) return;
    unawaited(_ensureTokenAndTopic(uid));
  }

  String _topicFor(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return '';
    return '${_activeRole}_$id';
  }

  Future<void> _ensureTokenAndTopic(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) return;
    if (_updatingToken) return;
    _updatingToken = true;
    try {
      // One-time migration: older builds could leave a device subscribed to
      // multiple uid topics. Deleting the FCM token clears all topic subscriptions.
      // We do this once per install to prevent caregiver/admin notifications
      // leaking into the wrong account on the same device.
      try {
        final dir = await getApplicationDocumentsDirectory();
        final marker = File('${dir.path}${Platform.pathSeparator}$_tokenResetMarkerFile');
        final alreadyReset = await marker.exists();
        if (!alreadyReset) {
          try {
            await _fm.deleteToken();
          } catch (_) {}
          try {
            await marker.writeAsString(
              DateTime.now().toIso8601String(),
              flush: true,
            );
          } catch (_) {}
        }
      } catch (_) {}

      // If the signed-in account changed on this device, perform a hard reset.
      // This guarantees the device is not still subscribed to the previous
      // account topics even if unsubscribe propagation is delayed.
      final previousTopic = _currentTopic;
      final nextTopic = _topicFor(trimmedUid);
      if (previousTopic != null &&
          previousTopic.trim().isNotEmpty &&
          nextTopic.isNotEmpty &&
          previousTopic.trim() != nextTopic) {
        try {
          await _tokenRefreshSub?.cancel();
        } catch (_) {}
        _tokenRefreshSub = null;
        try {
          await _fm.deleteToken();
        } catch (_) {}
        _currentTopic = null;
      }

      final token = await _fm.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _saveToken(trimmedUid, token.trim());
      }

      // Subscribe only to the currently signed-in uid. This prevents one device
      // from receiving notifications for multiple accounts.
      if (nextTopic.isNotEmpty && _currentTopic != nextTopic) {
        final previous = _currentTopic;
        _currentTopic = nextTopic;
        if (previous != null && previous.trim().isNotEmpty) {
          try {
            await _fm.unsubscribeFromTopic(previous.trim());
          } catch (_) {}
        }
        try {
          await _fm.subscribeToTopic(nextTopic);
        } catch (_) {}
      }

      // Token refresh: save the refreshed token and re-subscribe to the current uid.
      _tokenRefreshSub ??= _fm.onTokenRefresh.listen((t) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid.trim();
        if (currentUid == null || currentUid.isEmpty) return;
        try {
          await _saveToken(currentUid, t.trim());
        } catch (_) {}
        try {
          final currentTopic = _topicFor(currentUid);
          if (currentTopic.isNotEmpty && _currentTopic != currentTopic) {
            final prev = _currentTopic;
            _currentTopic = currentTopic;
            if (prev != null && prev.trim().isNotEmpty) {
              await _fm.unsubscribeFromTopic(prev.trim());
            }
          }
          if (currentTopic.isNotEmpty) {
            await _fm.subscribeToTopic(currentTopic);
          }
        } catch (_) {}
      });
    } finally {
      _updatingToken = false;
    }
  }

  Future<void> _handleSignedOut() async {
    // The safest way to stop receiving previous account notifications on the same
    // device is to delete the FCM token (topic subscriptions are token-scoped).
    try {
      await _tokenRefreshSub?.cancel();
    } catch (_) {}
    _tokenRefreshSub = null;

    final previous = _currentTopic;
    _currentTopic = null;
    if (previous != null && previous.trim().isNotEmpty) {
      try {
        await _fm.unsubscribeFromTopic(previous.trim());
      } catch (_) {}
    }
    try {
      await _fm.deleteToken();
    } catch (_) {}
  }

  Future<void> _saveToken(String uid, String token) async {
    final firestore = FirebaseFirestore.instance;
    final role = _activeRole;
    if (role == _roleAdmin) {
      await firestore
          .collection('admin')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      return;
    }
    if (role == _roleCaregiver) {
      await firestore
          .collection('caregivers')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      return;
    }
    await firestore
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
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
        icon: 'ic_notification',
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
