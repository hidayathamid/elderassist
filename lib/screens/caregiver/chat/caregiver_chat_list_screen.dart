import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../chat/chat_list_screen.dart';

class CaregiverChatListScreen extends StatelessWidget {
  const CaregiverChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final chatService = ChatService();
    final caregiverId = auth.userId;

    return ChatListScreen(
      title: 'Messages',
      stream: chatService.streamCaregiverChats(caregiverId),
      userId: caregiverId,
      hideCallAction: true,
    );
  }
}
