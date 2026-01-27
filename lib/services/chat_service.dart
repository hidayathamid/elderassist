import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

import '../models/chat_message_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _normalizeId(String value) => value.trim();

  String _chatKey({
    required String userId,
    required String caregiverId,
    String? personId,
  }) {
    final a = _normalizeId(userId);
    final b = _normalizeId(caregiverId);
    final ids = [a, b]..sort();
    final p = (personId ?? '').trim();
    return p.isEmpty ? '${ids[0]}_${ids[1]}' : '${ids[0]}_${ids[1]}_$p';
  }

  bool _isUnreadMessageFor(String receiverId, Map<String, dynamic> data) {
    if (receiverId.isEmpty) return false;
    if (data['readAt'] != null) return false;
    if ((data['receiverId'] as String?)?.trim() != receiverId) return false;
    if (data['isDeleted'] == true) return false;
    final hiddenFor = (data['hiddenFor'] as List?)?.whereType<String>().toList();
    if (hiddenFor != null && hiddenFor.contains(receiverId)) return false;
    return true;
  }

  /// ------------------------------------------------------------
  /// 1. CREATE OR GET CHAT ROOM
  /// ------------------------------------------------------------
  Future<String> createOrGetChat(
    String userId,
    String caregiverId, {
    String? personId,
  }) async {
    try {
      final trimmedUserId = _normalizeId(userId);
      final trimmedCaregiverId = _normalizeId(caregiverId);
      final trimmedPersonId = (personId ?? '').trim();
      if (trimmedUserId.isEmpty || trimmedCaregiverId.isEmpty) return '';
      if (trimmedUserId == trimmedCaregiverId) return '';

      // Check if chat already exists
      final existing = await _db
          .collection("chats")
          .where("participants", arrayContains: trimmedUserId)
          .get();

      for (var doc in existing.docs) {
        final data = doc.data();
        final participants = (data["participants"] as List?)
                ?.whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            <String>[];
        if (participants.length != 2) {
          continue;
        }

        if (participants.contains(trimmedCaregiverId) &&
            participants.contains(trimmedUserId)) {
          final existingPersonId = (data['personId'] as String?)?.trim() ?? '';
          final targetPersonId = trimmedPersonId;
          final matchPerson = existingPersonId.isEmpty && targetPersonId.isEmpty
              ? true
              : existingPersonId == targetPersonId;
          if (!matchPerson) {
            continue;
          }

          final key = _chatKey(
            userId: trimmedUserId,
            caregiverId: trimmedCaregiverId,
            personId: trimmedPersonId,
          );
          _db.collection("chats").doc(doc.id).set(
            {
              "chatKey": key,
              "userId": trimmedUserId,
              "caregiverId": trimmedCaregiverId,
            },
            SetOptions(merge: true),
          );
          return doc.id;
        }
      }

      // Otherwise create new chat room (use stable key to avoid duplicates)
      final key = _chatKey(
        userId: trimmedUserId,
        caregiverId: trimmedCaregiverId,
        personId: trimmedPersonId,
      );
      final ref = _db.collection("chats").doc(key);
      final snap = await ref.get();
      if (snap.exists) return ref.id;

      final newChatData = <String, dynamic>{
        "chatKey": key,
        "participants": [trimmedUserId, trimmedCaregiverId],
        "userId": trimmedUserId,
        "caregiverId": trimmedCaregiverId,
        "lastMessage": "",
        "lastTimestamp": null,
        "hasMessages": false,
        "createdAt": FieldValue.serverTimestamp(),
      };
      if (trimmedPersonId.isNotEmpty) {
        newChatData['personId'] = trimmedPersonId;
      }
      await ref.set(newChatData, SetOptions(merge: true));
      return ref.id;
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
      final trimmedChatId = chatId.trim();
      final trimmedSenderId = senderId.trim();
      final trimmedReceiverId = receiverId.trim();
      if (trimmedChatId.isEmpty ||
          trimmedSenderId.isEmpty ||
          trimmedReceiverId.isEmpty) {
        return false;
      }

      // Add message
      await _db
          .collection("chats")
          .doc(trimmedChatId)
          .collection("messages")
          .add({
        "senderId": trimmedSenderId,
        "receiverId": trimmedReceiverId,
        "text": text,
        if (imageUrl != null) "imageUrl": imageUrl,
        "timestamp": FieldValue.serverTimestamp(),
        "readAt": null,
        "isDeleted": false,
        "deletedBy": null,
        "hiddenFor": <String>[],
      });

      // Update chat summary so chat list can show last message + timestamp
      await _db.collection("chats").doc(trimmedChatId).set({
        "lastMessage": imageUrl != null ? 'Photo' : text,
        "lastTimestamp": FieldValue.serverTimestamp(),
        "hasMessages": true,
        // If someone previously removed the chat, make it visible again on new message.
        "hidden": {
          trimmedSenderId: false,
          trimmedReceiverId: false,
        },
      }, SetOptions(merge: true));

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

  Stream<int> streamUnreadCountForChat(String chatId, String receiverId) {
    if (chatId.isEmpty || receiverId.isEmpty) {
      return Stream<int>.value(0);
    }

    // Important: user can "clear" a chat (via `clearedAt[userId]`), which hides
    // older messages in the UI. Unread badges should not count messages that are
    // no longer visible due to `clearedAt`, otherwise the user sees "unread"
    // but opening the chat shows nothing new.
    final trimmedChatId = chatId.trim();
    final trimmedReceiverId = receiverId.trim();
    final controller = StreamController<int>.broadcast();

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? chatSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? messagesSub;
    Timestamp? lastClearedAt;

    void emitFromSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
      final total = snapshot.docs.fold<int>(0, (acc, doc) {
        final data = doc.data();
        if (!_isUnreadMessageFor(trimmedReceiverId, data)) return acc;
        if (lastClearedAt != null) {
          final ts = data['timestamp'];
          if (ts is Timestamp) {
            if (ts.compareTo(lastClearedAt!) <= 0) return acc;
          } else {
            // If timestamp is missing, treat it as not visible when clearedAt is set.
            return acc;
          }
        }
        return acc + 1;
      });
      if (!controller.isClosed) controller.add(total);
    }

    void resubscribeMessages() {
      messagesSub?.cancel();
      Query<Map<String, dynamic>> query = _db
          .collection("chats")
          .doc(trimmedChatId)
          .collection("messages")
          .where("receiverId", isEqualTo: trimmedReceiverId)
          .where("readAt", isNull: true);

      if (lastClearedAt != null) {
        query = query.where('timestamp', isGreaterThan: lastClearedAt);
      }

      messagesSub = query.snapshots().listen(
        emitFromSnapshot,
        onError: controller.addError,
      );
    }

    // Seed with no clearedAt until we load chat doc.
    resubscribeMessages();

    chatSub = _db
        .collection("chats")
        .doc(trimmedChatId)
        .snapshots()
        .listen(
      (chatSnap) {
        final data = chatSnap.data();
        final clearedMap = (data?['clearedAt'] as Map?)?.cast<String, dynamic>();
        final clearedValue = clearedMap?[trimmedReceiverId];
        final nextCleared = clearedValue is Timestamp ? clearedValue : null;

        final changed = (nextCleared?.seconds != lastClearedAt?.seconds) ||
            (nextCleared?.nanoseconds != lastClearedAt?.nanoseconds);
        if (!changed) return;
        lastClearedAt = nextCleared;
        resubscribeMessages();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await chatSub?.cancel();
      await messagesSub?.cancel();
      await controller.close();
    };

    return controller.stream.distinct();
  }

  bool _isChatHiddenFor(String participantId, Map<String, dynamic> data) {
    final hiddenValue = data['hidden'];
    if (hiddenValue is bool) return hiddenValue;
    if (hiddenValue is Map) {
      final map = hiddenValue.cast<String, dynamic>();
      return map[participantId] == true;
    }
    return false;
  }

  Stream<int> streamUnreadCountForParticipant(String participantId) {
    if (participantId.isEmpty) return Stream<int>.value(0);

    final controller = StreamController<int>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? chatsSub;
    final messageSubs = <String, StreamSubscription<int>>{};
    final unreadByChat = <String, int>{};

    void emit() {
      if (controller.isClosed) return;
      final total = unreadByChat.values.fold<int>(0, (a, b) => a + b);
      controller.add(total);
    }

    void subscribeToChat(String chatId) {
      if (messageSubs.containsKey(chatId)) return;
      messageSubs[chatId] = streamUnreadCountForChat(chatId, participantId).listen(
        (unreadCount) {
          unreadByChat[chatId] = unreadCount;
          emit();
        },
        onError: controller.addError,
      );
    }

    chatsSub = _db
        .collection("chats")
        .where("participants", arrayContains: participantId)
        .snapshots()
        .listen(
      (snapshot) {
        final nextChatIds = <String>{};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (_isChatHiddenFor(participantId, data)) continue;
          nextChatIds.add(doc.id);
          subscribeToChat(doc.id);
        }

        final removed = messageSubs.keys.where((id) => !nextChatIds.contains(id)).toList();
        for (final chatId in removed) {
          messageSubs.remove(chatId)?.cancel();
          unreadByChat.remove(chatId);
        }
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await chatsSub?.cancel();
      for (final sub in messageSubs.values) {
        await sub.cancel();
      }
      await controller.close();
    };

    return controller.stream.distinct();
  }

  Future<void> markChatMessagesRead({
    required String chatId,
    required String receiverId,
  }) async {
    if (chatId.isEmpty || receiverId.isEmpty) return;

    final query = await _db
        .collection("chats")
        .doc(chatId)
        .collection("messages")
        .where("receiverId", isEqualTo: receiverId)
        .where("readAt", isNull: true)
        .get();

    if (query.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in query.docs) {
      final data = doc.data();
      if (!_isUnreadMessageFor(receiverId, data)) continue;
      batch.update(doc.reference, {"readAt": FieldValue.serverTimestamp()});
    }
    await batch.commit();
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
    final trimmedChatId = chatId.trim();
    final trimmedUserId = userId.trim();
    if (trimmedChatId.isEmpty || trimmedUserId.isEmpty) return;

    final ref = _db.collection('chats').doc(trimmedChatId);
    final clearedAt = FieldValue.serverTimestamp();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? const <String, dynamic>{};

      final hiddenValue = data['hidden'];
      final Map<String, dynamic> nextHidden = {};
      if (hiddenValue is Map) {
        nextHidden.addAll(hiddenValue.cast<String, dynamic>());
      }
      nextHidden[trimmedUserId] = true;

      final clearedValue = data['clearedAt'];
      final Map<String, dynamic> nextCleared = {};
      if (clearedValue is Map) {
        nextCleared.addAll(clearedValue.cast<String, dynamic>());
      }
      nextCleared[trimmedUserId] = clearedAt;

      tx.set(
        ref,
        {
          'hidden': nextHidden,
          'clearedAt': nextCleared,
        },
        SetOptions(merge: true),
      );
    });

    // Clear unread messages for this user so old unread won't come back later.
    try {
      final query = await _db
          .collection("chats")
          .doc(trimmedChatId)
          .collection("messages")
          .where("receiverId", isEqualTo: trimmedUserId)
          .where("readAt", isNull: true)
          .get();
      if (query.docs.isEmpty) return;
      var batch = _db.batch();
      var ops = 0;
      for (final doc in query.docs) {
        batch.update(doc.reference, {"readAt": FieldValue.serverTimestamp()});
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    } catch (_) {
      // ignore failures; the hide flag still works
    }
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
    return streamUnreadCountForParticipant(userId);
  }

  Stream<int> streamUnreadCountForCaregiver(String caregiverId) {
    return streamUnreadCountForParticipant(caregiverId);
  }

  Stream<int> streamUnreadCountForConversation({
    required String participantId,
    required String otherUserId,
  }) {
    if (participantId.isEmpty || otherUserId.isEmpty) {
      return Stream<int>.value(0);
    }

    final controller = StreamController<int>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? chatsSub;
    final messageSubs = <String, StreamSubscription<int>>{};
    final unreadByChat = <String, int>{};

    void emit() {
      if (controller.isClosed) return;
      final total = unreadByChat.values.fold<int>(0, (a, b) => a + b);
      controller.add(total);
    }

    bool isConversationChat(Map<String, dynamic> data) {
      final participants =
          (data['participants'] as List?)?.whereType<String>().toList() ?? <String>[];
      return participants.contains(participantId) && participants.contains(otherUserId);
    }

    chatsSub = _db
        .collection("chats")
        .where("participants", arrayContains: participantId)
        .snapshots()
        .listen(
      (snapshot) {
        final nextChatIds = <String>{};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (_isChatHiddenFor(participantId, data)) continue;
          if (!isConversationChat(data)) continue;
          nextChatIds.add(doc.id);
          if (!messageSubs.containsKey(doc.id)) {
            messageSubs[doc.id] =
                streamUnreadCountForChat(doc.id, participantId).listen(
              (unreadCount) {
                unreadByChat[doc.id] = unreadCount;
                emit();
              },
              onError: controller.addError,
            );
          }
        }

        final removed = messageSubs.keys.where((id) => !nextChatIds.contains(id)).toList();
        for (final chatId in removed) {
          messageSubs.remove(chatId)?.cancel();
          unreadByChat.remove(chatId);
        }
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await chatsSub?.cancel();
      for (final sub in messageSubs.values) {
        await sub.cancel();
      }
      await controller.close();
    };

    return controller.stream.distinct();
  }
 }
