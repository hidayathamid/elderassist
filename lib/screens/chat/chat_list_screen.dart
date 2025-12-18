import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_screen.dart';
import '../user/chat/user_chat_screen.dart';

const double _chatCardRadius = 16;
const double _chatCardRevealExtent = 118;
const Color _chatMutedText = Color(0xFF1B1D29);

final BoxShadow _chatCardShadow = BoxShadow(
  color: Colors.black.withOpacity(0.08),
  blurRadius: 16,
  offset: const Offset(0, 4),
);

final DateFormat _timeFormatter = DateFormat.jm();

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.title,
    required this.stream,
    required this.userId,
    this.hideCallAction = false,
    this.onBack,
    this.actions,
  });

  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String userId;
  final bool hideCallAction;
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

  Widget _buildUnreadBanner(int totalUnread) {
    if (totalUnread == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: activityAccentBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activityAccentBlue.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.mark_email_unread, size: 18, color: activityAccentBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You have $totalUnread unread ${totalUnread == 1 ? 'messaremovege' : 'messages'}.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: activityPrimaryTextColor,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: activityAccentBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                totalUnread.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteBackground(VoidCallback onDelete) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: const [
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildProfileStyleAppBar(
        title: widget.title,
        onBack: widget.onBack,
        actions: widget.actions,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load chats: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: _chatMutedText),
              ),
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
            return !_isChatDocHidden(doc) && !_hiddenChatIds.contains(doc.id);
          }).toList();
          if (visibleChats.isEmpty) {
            return const Center(
              child: Text(
                'No chats yet',
                style: TextStyle(fontSize: 16, color: _chatMutedText),
              ),
            );
          }

          final totalUnread = visibleChats.fold<int>(
            0,
            (sum, doc) => sum + _extractUnread(doc, widget.userId),
          );

          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUnreadBanner(totalUnread),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: visibleChats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                        padding: const EdgeInsets.symmetric(vertical: 6),
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

                              return _ChatTile(
                                chatId: chatDoc.id,
                                currentUserId: widget.userId,
                                otherUserId: otherUserId,
                                displayName: displayName,
                                photoUrl: photoUrl,
                                lastMessage: lastMessage,
                                timeText: timeText,
                                unread: unread,
                                hideCallAction: widget.hideCallAction,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_chatCardRadius),
        border: Border.all(color: Colors.grey.shade200),
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                DefaultProfileAvatar(
                  radius: 24,
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
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: activityPrimaryTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: activityAccentBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unread.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lastMessage.isNotEmpty
                            ? lastMessage
                            : 'No messages yet',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Icon(
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
    setState(() {
      _dragOffset = shouldReveal ? widget.revealExtent : 0.0;
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
