import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_screen.dart';
import '../user/chat/user_chat_screen.dart';

const double _chatCardRadius = 18;
const double _chatCardRevealExtent = 118;
const Color _chatMutedText = Color(0xFF1B1D29);
const Color _chatPageBackground = Color(0xFFF7F8FA);
const Color _chatCardBorder = Color(0xFFE1E4EA);

final BoxShadow _chatCardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.08),
  blurRadius: 18,
  offset: const Offset(0, 9),
);

final DateFormat _timeFormatter = DateFormat.jm();

const TextStyle _sectionHeaderTextStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _chatMutedText,
  letterSpacing: -0.15,
);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.title,
    required this.stream,
    required this.userId,
    this.hideCallAction = false,
    this.includeChat,
    this.onBack,
    this.actions,
  });

  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String userId;
  final bool hideCallAction;
  final bool Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? includeChat;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final Set<String> _hiddenChatIds = <String>{};
  final ChatService _chatService = ChatService();
  String? _resetSwipeFor;

  void _hideChatLocally(String chatId) {
    setState(() => _hiddenChatIds.add(chatId));
  }

  Future<void> _deleteChat(String chatId) async {
    _hideChatLocally(chatId);
    await _chatService.markChatHidden(chatId, widget.userId);
  }

  bool _isChatDocHidden(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final hiddenValue = data['hidden'];
    if (hiddenValue is bool) return hiddenValue;
    if (hiddenValue is Map) {
      final map = hiddenValue.cast<String, dynamic>();
      return map[widget.userId] == true;
    }
    return false;
  }

  Future<bool> _confirmDeleteChat(
    QueryDocumentSnapshot<Map<String, dynamic>> chatDoc,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove from chats',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will remove the conversation from your list.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: activityButtonYellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text(
                'Remove',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    await _deleteChat(chatDoc.id);
    if (!mounted) return true;
    setState(() => _resetSwipeFor = chatDoc.id);
    return true;
  }

  Future<Map<String, dynamic>?> _fetchParticipant(String userId) async {
    if (userId.isEmpty) return null;
    final caregiverSnap = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(userId)
        .get();
    if (caregiverSnap.exists) {
      return caregiverSnap.data();
    }
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (userSnap.exists) {
      return userSnap.data();
    }
    return null;
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final moment = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(moment);
    if (diff.inDays == 0) {
      return _timeFormatter.format(moment);
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return DateFormat.E().format(moment);
    }
    return DateFormat('MMM d').format(moment);
  }

  int _compareByTimestamp(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final timestampA = a.data()['lastTimestamp'] as Timestamp?;
    final timestampB = b.data()['lastTimestamp'] as Timestamp?;
    if (timestampA == null && timestampB == null) return 0;
    if (timestampA == null) return 1;
    if (timestampB == null) return -1;
    return timestampB.compareTo(timestampA);
  }

  int _extractUnread(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String userId,
  ) {
    final data = doc.data();
    return ChatService.unreadFromDocument(data, userId);
  }

  Widget _buildDeleteBackground(VoidCallback onDelete) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(_chatCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_chatCardRadius),
          onTap: onDelete,
          child: const _DeleteLabel(alignment: Alignment.centerLeft),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatPageBackground,
      appBar: buildProfileStyleAppBar(
        title: widget.title,
        onBack: widget.onBack,
        actions: widget.actions,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildEmptyGuidance(
              icon: Icons.chat,
              headline: 'Unable to load chats',
              explanation: snapshot.error?.toString() ?? 'Please try again.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];
          final sortedChats =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(chats)
                ..sort(_compareByTimestamp);
          final visibleChats = sortedChats.where((doc) {
            if (_isChatDocHidden(doc) || _hiddenChatIds.contains(doc.id)) {
              return false;
            }
            final data = doc.data();
            final participants =
                (data['participants'] as List?)?.whereType<String>().toList() ??
                    <String>[];
            if (participants.length != 2) {
              return false;
            }
            if (!participants.contains(widget.userId)) {
              return false;
            }
            final hasMessages = data['hasMessages'] == true;
            final lastMessage = (data['lastMessage'] as String?)?.trim() ?? '';
            if (!hasMessages && lastMessage.isEmpty) {
              return false;
            }
            final filter = widget.includeChat;
            if (filter != null && !filter(doc)) return false;
            return true;
          }).toList();
          if (visibleChats.isEmpty) {
            return _buildEmptyGuidance(
              icon: Icons.chat,
              headline: 'No chats yet',
              explanation: 'Start a conversation after you book a caregiver.',
            );
          }

           return Padding(
             padding: const EdgeInsets.only(top: 12),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.stretch,
               children: [
                 const Padding(
                   padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                   child: Text('Conversations', style: _sectionHeaderTextStyle),
                 ),
                 Expanded(
                   child: ListView.separated(
                     padding: const EdgeInsets.symmetric(
                       vertical: 0,
                       horizontal: 12,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: visibleChats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 3),
                    itemBuilder: (context, index) {
                      final chatDoc = visibleChats[index];
                      final data = chatDoc.data();
                      final participants = List<String>.from(
                        data['participants'] ?? <String>[],
                      );
                      final otherUserId = participants.firstWhere(
                        (id) => id != widget.userId,
                        orElse: () => '',
                      );
                      final lastMessage =
                          (data['lastMessage'] as String?) ?? '';
                      final timestamp = data['lastTimestamp'] as Timestamp?;
                      final timeText = _formatTimestamp(timestamp);
                      final unread = _extractUnread(chatDoc, widget.userId);

                      return Padding(
                        key: ValueKey(chatDoc.id),
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: _ChatSwipeRevealCard(
                          id: chatDoc.id,
                          resetId: _resetSwipeFor,
                          revealExtent: _chatCardRevealExtent,
                          background: _buildDeleteBackground(
                            () => _confirmDeleteChat(chatDoc),
                          ),
                          child: FutureBuilder<Map<String, dynamic>?>(
                            future: _fetchParticipant(otherUserId),
                            builder: (context, participantSnapshot) {
                              final participant = participantSnapshot.data;
                              final personName = (data['personName'] as String?)
                                  ?.trim();
                              final fallback =
                                  (participant?['name'] as String?) ??
                                  (participant?['fullName'] as String?) ??
                                  (data['chatLabel'] as String?) ??
                                  (data['otherUserName'] as String?) ??
                                  (otherUserId.isNotEmpty ? 'Chat' : 'Room');
                              final displayName = personName?.isNotEmpty == true
                                  ? personName!
                                  : fallback;
                              final photoUrl =
                                  (participant?['photoUrl'] as String?) ??
                                  (participant?['avatar'] as String?) ??
                                  (data['photoUrl'] as String?) ??
                                  '';

                              return StreamBuilder<int>(
                                stream: _chatService.streamUnreadCountForChat(
                                  chatDoc.id,
                                  widget.userId,
                                ),
                                builder: (context, unreadSnapshot) {
                                  return _ChatTile(
                                    chatId: chatDoc.id,
                                    currentUserId: widget.userId,
                                    otherUserId: otherUserId,
                                    displayName: displayName,
                                    photoUrl: photoUrl,
                                    lastMessage: lastMessage,
                                    timeText: timeText,
                                    unread: unreadSnapshot.data ?? unread,
                                    hideCallAction: widget.hideCallAction,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _buildEmptyGuidance({
  required IconData icon,
  required String headline,
  required String explanation,
}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: activityAccentBlue),
            const SizedBox(height: 10),
            Text(
              headline,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: activityPrimaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              explanation,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chatId,
    required this.currentUserId,
    required this.otherUserId,
    required this.displayName,
    required this.photoUrl,
    required this.lastMessage,
    required this.timeText,
    required this.unread,
    required this.hideCallAction,
  });

  final String chatId;
  final String currentUserId;
  final String otherUserId;
  final String displayName;
  final String photoUrl;
  final String lastMessage;
  final String timeText;
  final int unread;
  final bool hideCallAction;

  Widget _buildUnreadPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: activityAccentBlue,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_chatCardRadius),
        border: Border.all(color: _chatCardBorder),
        boxShadow: [_chatCardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_chatCardRadius),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserChatScreen(
                  chatId: chatId,
                  otherUserId: otherUserId,
                  otherUserName: displayName,
                  hideCallAction: hideCallAction,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                DefaultProfileAvatar(
                  radius: 22,
                  photoUrl: photoUrl.trim().isEmpty ? null : photoUrl,
                  label: displayName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: activityPrimaryTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastMessage.isNotEmpty
                            ? lastMessage
                            : 'No messages yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.58),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    unread > 0
                        ? _buildUnreadPill(unread)
                        : const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Colors.black38,
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatSwipeRevealCard extends StatefulWidget {
  const _ChatSwipeRevealCard({
    required this.id,
    required this.resetId,
    required this.child,
    required this.background,
    required this.revealExtent,
  });

  final String id;
  final String? resetId;
  final Widget child;
  final Widget background;
  final double revealExtent;

  @override
  State<_ChatSwipeRevealCard> createState() => _ChatSwipeRevealCardState();
}

class _ChatSwipeRevealCardState extends State<_ChatSwipeRevealCard> {
  double _dragOffset = 0.0;
  bool _dragging = false;
  bool _dragActive = false;
  String? _lastResetId;

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_dragging) return;
    final deltaX = event.delta.dx;
    final deltaY = event.delta.dy;
    if (!_dragActive) {
      if (deltaX.abs() > 10 && deltaX.abs() > deltaY.abs()) {
        _dragActive = true;
      } else {
        return;
      }
    }
    if (deltaX < 0 && _dragOffset <= 0) return;
    setState(() {
      _dragOffset = (_dragOffset + deltaX).clamp(0.0, widget.revealExtent);
    });
  }

  void _handlePointerEnd() {
    final shouldReveal = _dragOffset >= widget.revealExtent * 0.5;
    final target = shouldReveal ? widget.revealExtent : 0.0;
    setState(() {
      _dragOffset = target;
      _dragging = false;
      _dragActive = false;
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    setState(() {
      _dragOffset = 0.0;
      _dragging = false;
      _dragActive = false;
    });
  }

  @override
  void didUpdateWidget(covariant _ChatSwipeRevealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetId != null &&
        widget.resetId == widget.id &&
        _lastResetId != widget.resetId) {
      setState(() {
        _dragOffset = 0.0;
        _dragging = false;
        _dragActive = false;
        _lastResetId = widget.resetId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _dragging = true;
        _dragActive = false;
      },
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _handlePointerEnd(),
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          Positioned.fill(child: widget.background),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _DeleteLabel extends StatelessWidget {
  const _DeleteLabel({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 20),
          SizedBox(width: 10),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
