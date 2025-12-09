import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/chat_service.dart';
import '../../../services/auth_service.dart';
import 'user_chat_screen.dart';

class UserChatListScreen extends StatefulWidget {
  const UserChatListScreen({super.key});

  @override
  _UserChatListScreenState createState() => _UserChatListScreenState();
}

class _UserChatListScreenState extends State<UserChatListScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    final userId = _auth.userId;

    return Scaffold(
      appBar: AppBar(title: const Text("Messages")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatService.streamUserChats(userId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snap.data!.docs;

          if (chats.isEmpty) {
            return const Center(child: Text("No messages yet."));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final doc = chats[index];
              final data = doc.data() as Map<String, dynamic>;
              final chatId = doc.id;

              final participants = List<String>.from(
                data["participants"] ?? [],
              );
              final otherUserId = participants.firstWhere(
                (id) => id != userId,
                orElse: () => "",
              );

              final lastMessage = data["lastMessage"] ?? "";
              final lastTimestamp = data["lastTimestamp"] as Timestamp?;
              final timeText = lastTimestamp != null
                  ? TimeOfDay.fromDateTime(
                      lastTimestamp.toDate(),
                    ).format(context)
                  : "";

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text("Chat with $otherUserId"),
                subtitle: Text(lastMessage),
                trailing: Text(timeText),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserChatScreen(
                        chatId: chatId,
                        otherUserId: otherUserId,
                        otherUserName: "Caregiver",
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
