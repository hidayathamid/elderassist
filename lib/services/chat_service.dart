import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_message_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ------------------------------------------------------------
  /// 1. CREATE OR GET CHAT ROOM
  /// ------------------------------------------------------------
  Future<String> createOrGetChat(
    String userId,
    String caregiverId, {
    String? personId,
  }) async {
    try {
      // Check if chat already exists
      final existing = await _db
          .collection("chats")
          .where("participants", arrayContains: userId)
          .get();

      for (var doc in existing.docs) {
        final data = doc.data();
        final List<dynamic> participants = data["participants"] ?? [];

        if (participants.contains(caregiverId)) {
          final existingPersonId = (data['personId'] as String?)?.trim() ?? '';
          final targetPersonId = personId?.trim() ?? '';
          final matchPerson = existingPersonId.isEmpty && targetPersonId.isEmpty
              ? true
              : existingPersonId == targetPersonId;
          if (!matchPerson) {
            continue;
          }
          return doc.id;
        }
      }

      // Otherwise create new chat room
      final newChatData = {
        "participants": [userId, caregiverId],
        "lastMessage": "",
        "lastTimestamp": FieldValue.serverTimestamp(),
      };
      final normalizedPersonId = personId?.trim();
      if (normalizedPersonId?.isNotEmpty == true) {
        newChatData['personId'] = normalizedPersonId!;
      }
      final newChat = await _db.collection("chats").add(newChatData);

      return newChat.id;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> setChatLabel(String chatId, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    await _db.collection("chats").doc(chatId).set({
      "chatLabel": trimmed,
      "otherUserName": trimmed,
    }, SetOptions(merge: true));
  }

  Future<void> setChatPersonInfo(
    String chatId, {
    String? personId,
    String? personName,
  }) async {
    final Map<String, dynamic> updates = {};
    final cleanedId = personId?.trim();
    if (cleanedId?.isNotEmpty == true) {
      updates['personId'] = cleanedId;
    }
    final cleanedName = personName?.trim();
    if (cleanedName?.isNotEmpty == true) {
      updates['personName'] = cleanedName;
    }
    if (updates.isEmpty) return;
    await _db
        .collection("chats")
        .doc(chatId)
        .set(updates, SetOptions(merge: true));
  }

  /// OPTIONAL: create chat using booking information
  Future<String> getOrCreateChatByBooking(
    String userId,
    String caregiverId,
    String bookingId,
  ) async {
    return createOrGetChat(userId, caregiverId);
  }

  /// ------------------------------------------------------------
  /// 2. SEND MESSAGE + UPDATE CHAT SUMMARY
  /// ------------------------------------------------------------
  Future<String> uploadChatImage(String chatId, XFile file) async {
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(' ', '_')}';
    final ref = FirebaseStorage.instance.ref().child(
      'chats/$chatId/images/$filename',
    );

    if (kIsWeb) {
      final data = await file.readAsBytes();
      await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
    } else {
      await ref.putFile(File(file.path));
    }

    return ref.getDownloadURL();
  }

  Future<bool> sendMessage(
    String chatId,
    String senderId,
    String receiverId,
    String text, {
    String? imageUrl,
  }) async {
    if (text.trim().isEmpty && imageUrl == null) return false;

    try {
      // Add message
      await _db.collection("chats").doc(chatId).collection("messages").add({
        "senderId": senderId,
        "receiverId": receiverId,
        "text": text,
        if (imageUrl != null) "imageUrl": imageUrl,
        "timestamp": FieldValue.serverTimestamp(),
        "readAt": null,
        "isDeleted": false,
        "deletedBy": null,
        "hiddenFor": <String>[],
      });

      // Update chat summary so chat list can show last message + timestamp
      await _db.collection("chats").doc(chatId).update({
        "lastMessage": imageUrl != null ? 'Photo' : text,
        "lastTimestamp": FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// ------------------------------------------------------------
  /// 3. STREAM MESSAGES FOR CHAT SCREEN
  /// ------------------------------------------------------------
  Stream<List<ChatMessageModel>> streamMessages(String chatId) {
    return _db
        .collection("chats")
        .doc(chatId)
        .collection("messages")
        .orderBy("timestamp")
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ChatMessageModel.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// ------------------------------------------------------------
  /// 4. STREAM USER CHAT LIST
  /// ------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> streamUserChats(String userId) {
    return _db
        .collection("chats")
        .where("participants", arrayContains: userId)
        .snapshots();
  }

  /// ------------------------------------------------------------
  /// 5. STREAM CAREGIVER CHAT LIST
  /// ------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> streamCaregiverChats(
    String caregiverId,
  ) {
    return _db
        .collection("chats")
        .where("participants", arrayContains: caregiverId)
        .snapshots();
  }

  /// ------------------------------------------------------------
  /// 6. MANAGE MESSAGES
  /// ------------------------------------------------------------
  Future<void> updateMessageText(
    String chatId,
    String messageId,
    String updatedText,
  ) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'text': updatedText});
  }

  Future<void> deleteMessage(
    String chatId,
    ChatMessageModel message, {
    required String userId,
    bool removeFromScreen = false,
  }) async {
    final docRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(message.messageId);

    if (removeFromScreen) {
      await docRef.update({
        'hiddenFor': FieldValue.arrayUnion([userId]),
      });
      return;
    }

    final Map<String, dynamic> updates = {
      'isDeleted': true,
      'deletedBy': userId,
      'text': '',
      'imageUrl': null,
    };

    await docRef.update(updates);

    if (message.imageUrl != null && message.imageUrl!.isNotEmpty) {
      await _deleteImageFromStorage(message.imageUrl!);
    }
  }

  Future<void> _deleteImageFromStorage(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
    } catch (_) {
      // ignore failures to delete storage objects
    }
  }

  Future<void> markChatHidden(String chatId, String userId) async {
    await _db.collection('chats').doc(chatId).set({
      'hidden.$userId': true,
    }, SetOptions(merge: true));
  }

  static int unreadFromDocument(
    Map<String, dynamic> data,
    String participantId,
  ) {
    final unreadCounts = (data['unreadCounts'] as Map?)?.cast<String, dynamic>();
    return (unreadCounts?[participantId] as int?) ??
        (data['unread'] as int?) ??
        0;
  }

  Stream<int> streamUnreadCountForUser(String userId) {
    return streamUserChats(userId).map(
      (snapshot) => snapshot.docs.fold(
        0,
        (total, doc) => total + unreadFromDocument(doc.data(), userId),
      ),
    );
  }

  Stream<int> streamUnreadCountForCaregiver(String caregiverId) {
    return streamCaregiverChats(caregiverId).map(
      (snapshot) => snapshot.docs.fold(
        0,
        (total, doc) =>
            total + unreadFromDocument(doc.data(), caregiverId),
      ),
    );
  }
 }
