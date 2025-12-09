import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/chat_service.dart';
import '../../../services/auth_service.dart';
import 'caregiver_chat_screen.dart';

class CaregiverChatListScreen extends StatelessWidget {
  const CaregiverChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final caregiverId = auth.userId;
    final chatService = ChatService();

    return Scaffold(
      appBar: AppBar(title: const Text("Chats")),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatService.streamCaregiverChats(caregiverId),
        builder: (_, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No chats yet", style: TextStyle(fontSize: 16)),
            );
          }

          final chats = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final chat = chats[i];
              final chatId = chat.id;
              final data = chat.data() as Map<String, dynamic>;

              final lastMessage = (data["lastMessage"] ?? "") as String;

              final timestamp = data["lastTimestamp"];
              String timeText = "";
              if (timestamp is Timestamp) {
                final dt = timestamp.toDate();
                final hh = dt.hour.toString().padLeft(2, '0');
                final mm = dt.minute.toString().padLeft(2, '0');
                timeText = "$hh:$mm";
              }

              // Participants list → cari client/user id (bukan caregiver)
              final participants = List<String>.from(
                data["participants"] ?? <String>[],
              );
              final otherUserId = participants.firstWhere(
                (id) => id != caregiverId,
                orElse: () => "",
              );

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                    otherUserId.isNotEmpty
                        ? "Client: $otherUserId"
                        : "Chat Room",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(timeText),
                      const SizedBox(height: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CaregiverChatScreen(
                          chatId: chatId,
                          otherUserId: otherUserId,
                          contactName: otherUserId.isNotEmpty
                              ? "Client"
                              : "Chat Room",
                          lastSeen: timeText,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
