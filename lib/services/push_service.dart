import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    // iOS permission
    if (Platform.isIOS) {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
    }

    // get and save token if signed in
    await _updateToken();
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) await _updateToken();
    });

    // foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('FCM onMessage: ${message.data}');
      }
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

  Future<void> _updateToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await _fm.getToken();
      if (token != null) {
        await _saveToken(user.uid, token);
      }
      // token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        await _saveToken(user.uid, t);
      });
    } catch (_) {}
  }

  Future<void> _saveToken(String uid, String token) async {
    final firestore = FirebaseFirestore.instance;
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

  void _handleNavigation(
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navKey,
  ) {
    final chatId = data['chatId'] as String?;
    final otherId = data['otherUserId'] as String?;
    final otherName = data['otherUserName'] as String?;
    final bookingId = data['bookingId'] as String?;
    if (otherId != null && otherName != null) {
      navKey.currentState?.pushNamed(
        '/chat',
        arguments: {
          'chatId': chatId,
          'otherUserId': otherId,
          'otherUserName': otherName,
          'bookingId': bookingId,
        },
      );
    }
  }
}
