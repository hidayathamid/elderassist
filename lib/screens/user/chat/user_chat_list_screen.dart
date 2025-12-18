import 'package:flutter/material.dart';
import '../../../services/chat_service.dart';
import '../../../services/auth_service.dart';
import '../../chat/chat_list_screen.dart';

class UserChatListScreen extends StatelessWidget {
  const UserChatListScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final chatService = ChatService();
    final userId = auth.userId;

    return ChatListScreen(
      title: 'Messages',
      stream: chatService.streamUserChats(userId),
      userId: userId,
      hideCallAction: false,
      onBack: showBackButton ? () => Navigator.of(context).maybePop() : null,
    );
  }
}
