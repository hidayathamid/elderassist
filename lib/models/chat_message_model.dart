import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageModel {
  final String messageId;
  final String senderId;
  final String receiverId;
  final String text;
  final String? imageUrl;
  final Timestamp timestamp;
  final Timestamp? readAt;
  final bool isDeleted;
  final String? deletedBy;
  final List<String> hiddenFor;

  ChatMessageModel({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    this.readAt,
    this.isDeleted = false,
    this.deletedBy,
    List<String>? hiddenFor,
  }) : hiddenFor = hiddenFor ?? const [];

  factory ChatMessageModel.fromMap(String id, Map<String, dynamic> data) {
    return ChatMessageModel(
      messageId: id,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      readAt: data['readAt'] as Timestamp?,
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedBy: data['deletedBy'] as String?,
      hiddenFor: (data['hiddenFor'] as List?)?.cast<String>() ?? const [],
    );
  }
}
