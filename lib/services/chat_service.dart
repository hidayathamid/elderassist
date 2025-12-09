import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ------------------------------------------------------------
  /// 1. CREATE OR GET CHAT ROOM
  /// ------------------------------------------------------------
  Future<String> createOrGetChat(String userId, String caregiverId) async {
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
          return doc.id; // Chat already exists
        }
      }

      // Otherwise create new chat room
      final newChat = await _db.collection("chats").add({
        "participants": [userId, caregiverId],
        "lastMessage": "",
        "lastTimestamp": FieldValue.serverTimestamp(),
      });

      return newChat.id;
    } catch (e) {
      print("createOrGetChat ERROR: $e");
      rethrow;
    }
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
  Future<bool> sendMessage(
    String chatId,
    String senderId,
    String receiverId,
    String text,
  ) async {
    if (text.trim().isEmpty) return false;

    try {
      // Add message
      await _db.collection("chats").doc(chatId).collection("messages").add({
        "senderId": senderId,
        "receiverId": receiverId,
        "text": text,
        "timestamp": FieldValue.serverTimestamp(),
      });

      // Update chat summary so chat list can show last message + timestamp
      await _db.collection("chats").doc(chatId).update({
        "lastMessage": text,
        "lastTimestamp": FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print("sendMessage ERROR: $e");
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
  Stream<QuerySnapshot> streamUserChats(String userId) {
    return _db
        .collection("chats")
        .where("participants", arrayContains: userId)
        .orderBy("lastTimestamp", descending: true)
        .snapshots();
  }

  /// ------------------------------------------------------------
  /// 5. STREAM CAREGIVER CHAT LIST
  /// ------------------------------------------------------------
  Stream<QuerySnapshot> streamCaregiverChats(String caregiverId) {
    return _db
        .collection("chats")
        .where("participants", arrayContains: caregiverId)
        .orderBy("lastTimestamp", descending: true)
        .snapshots();
  }
}
