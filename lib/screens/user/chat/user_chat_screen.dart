
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../models/chat_message_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/safe_network_image.dart';

const Color _profileTextColor = Color(0xFF1B1D29);
const Color _profileBorderColor = Color(0xFFE0E0E0);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _bubbleYou = Color(0xFF3F3F3F);
const Color _bubbleMe = _tealAccent;
const double _containerRadius = 18;
const TextStyle _bubbleText = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: Colors.white,
);
final DateFormat _timeFormat = DateFormat('h:mm a');

enum _MessageAction { copy, edit, delete, saveImage, removeDeleted }

class UserChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final bool hideCallAction;

  const UserChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.hideCallAction = false,
  });

  @override
  State<UserChatScreen> createState() => _UserChatScreenState();
}

class _UserChatScreenState extends State<UserChatScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _auth = AuthService();
  final ImagePicker _picker = ImagePicker();

  late final Future<String?> _photoFuture;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _isUploadingImage = false;
  bool _markingRead = false;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();
  String? _editingMessageId;

  @override
  void initState() {
    super.initState();
    _photoFuture = _loadOtherUserPhoto();
  }

  Future<String?> _loadOtherUserPhoto() async {
    final caregiverDoc = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(widget.otherUserId)
        .get();
    final caregiverPhoto = (caregiverDoc.data()?['photoUrl'] as String?)
        ?.trim();
    if (caregiverPhoto?.isNotEmpty == true) {
      return caregiverPhoto;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();
    final userPhoto = (userDoc.data()?['photoUrl'] as String?)?.trim();
    if (userPhoto?.isNotEmpty == true) {
      return userPhoto;
    }

    return null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    final messageText = text ?? _controller.text.trim();
    if (messageText.isEmpty && imageUrl == null) return;

    final userId = _auth.userId;
    await _chatService.sendMessage(
      widget.chatId,
      userId,
      widget.otherUserId,
      messageText,
      imageUrl: imageUrl,
    );
    _controller.clear();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  bool get _isEditing => _editingMessageId != null;

  Future<void> _handleSend() async {
    if (_isUploadingImage) return;

    if (_isEditing) {
      final updatedText = _controller.text.trim();
      if (updatedText.isEmpty || _editingMessageId == null) return;
      try {
        await _chatService.updateMessageText(
          widget.chatId,
          _editingMessageId!,
          updatedText,
        );
        if (mounted) {}
      } catch (_) {
        if (mounted) {}
      } finally {
        _cancelEditing();
      }
      _scrollToBottom();
      return;
    }

    if (_selectedImage != null) {
      setState(() => _isUploadingImage = true);
      final currentText = _controller.text.trim();
      try {
        final url = await _chatService.uploadChatImage(
          widget.chatId,
          _selectedImage!,
        );
        await _sendMessage(text: currentText, imageUrl: url);
      } finally {
        if (mounted) {
          setState(() {
            _selectedImage = null;
            _selectedImageBytes = null;
            _isUploadingImage = false;
          });
        }
      }
    } else {
      await _sendMessage();
    }
  }

  Future<void> _maybeMarkMessagesRead(
    List<ChatMessageModel> messages,
    String userId,
  ) async {
    if (_markingRead) return;
    if (userId.isEmpty) return;
    final hasUnread = messages.any(
      (msg) =>
          msg.receiverId == userId &&
          msg.readAt == null &&
          !msg.isDeleted &&
          !msg.hiddenFor.contains(userId),
    );
    if (!hasUnread) return;

    _markingRead = true;
    try {
      await _chatService.markChatMessagesRead(
        chatId: widget.chatId,
        receiverId: userId,
      );
    } finally {
      _markingRead = false;
    }
  }

  Future<void> _openGallery() async {
    final XFile? result = await _picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;
    final bytes = await result.readAsBytes();
    setState(() {
      _selectedImage = result;
      _selectedImageBytes = bytes;
    });
  }

  Future<void> _openCamera() async {
    final XFile? result = await _picker.pickImage(source: ImageSource.camera);
    if (result == null) return;
    final bytes = await result.readAsBytes();
    setState(() {
      _selectedImage = result;
      _selectedImageBytes = bytes;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _buildDateLabel(DateTime reference) {
    final now = DateTime.now();
    if (_isSameDay(reference, now)) return 'Today';
    if (_isSameDay(reference, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMM d').format(reference);
  }

  Widget _buildDateHeader(List<ChatMessageModel> messages) {
    final timestamp = messages.isNotEmpty
        ? messages.first.timestamp.toDate()
        : DateTime.now();
    final label = _buildDateLabel(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _profileTextColor,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTimeAndTick(bool isMe, ChatMessageModel message) {
    return [
      Text(
        _timeFormat.format(message.timestamp.toDate().toLocal()),
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      if (isMe) ...[
        const SizedBox(width: 4),
        Icon(
          Icons.done_all,
          size: 14,
          color: message.readAt != null ? _tealAccent : Colors.white60,
        ),
      ],
    ];
  }

  Widget _buildBubbleContent(
    BuildContext context,
    ChatMessageModel message,
    bool isMe,
    String currentUserId,
  ) {
    if (message.isDeleted) {
      final deletedByMe = message.deletedBy == currentUserId;
      final placeholderText =
          deletedByMe ? 'You deleted this message.' : 'Message deleted.';
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              placeholderText,
              style: _bubbleText.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              textAlign: isMe ? TextAlign.right : TextAlign.left,
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildTimeAndTick(isMe, message),
          ),
        ],
      );
    }

    final hasImage = (message.imageUrl?.trim().isNotEmpty ?? false);
    if (hasImage) {
      return Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SafeNetworkImage(
              message.imageUrl!.trim(),
              width: MediaQuery.of(context).size.width * 0.6,
              height: 220,
              fit: BoxFit.cover,
              placeholder: Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined, color: Colors.black38),
              ),
              errorWidget: Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.black38,
                ),
              ),
            ),
          ),
          if (message.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                message.text,
                style: _bubbleText,
                textAlign: isMe ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.bottomRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _buildTimeAndTick(isMe, message),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            message.text,
            style: _bubbleText,
            textAlign: isMe ? TextAlign.right : TextAlign.left,
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _buildTimeAndTick(isMe, message),
        ),
      ],
    );
  }

  Future<void> _showMessageActions(
    BuildContext messageContext,
    ChatMessageModel message,
    bool isMe,
    String currentUserId,
  ) async {
    final renderBox = messageContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final target = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(messageContext).size;
    final menuWidth = 200.0;
    final maxLeft = math.max(screenSize.width - menuWidth - 12.0, 12.0);
    final menuLeft = target.dx.clamp(12.0, maxLeft);
    final maxTop = math.max(screenSize.height - 220.0, 12.0);
    final menuTop =
        (target.dy + size.height + 12.0).clamp(12.0, maxTop);

    final hasText = message.text.trim().isNotEmpty;
    final hasImage = message.imageUrl?.trim().isNotEmpty ?? false;
    final deletedByMe = message.deletedBy == currentUserId;
    final bool canCopy = !message.isDeleted && hasText;
    final bool canEdit = !message.isDeleted && isMe && hasText;
    final bool canSave = !message.isDeleted && hasImage;
    final bool canDelete = !message.isDeleted && isMe;
    final bool canRemovePlaceholder = message.isDeleted && deletedByMe;

    if (!(canCopy || canEdit || canSave || canDelete || canRemovePlaceholder)) {
      return;
    }

    final action = await showGeneralDialog<_MessageAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Message actions',
      pageBuilder: (dialogContext, __, ___) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withOpacity(0.15),
                  ),
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: menuTop,
              child: Material(
                color: Colors.white,
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: menuWidth,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canCopy)
                        _buildContextMenuOption(
                          dialogContext,
                          'Copy',
                          Icons.copy,
                          _MessageAction.copy,
                        ),
                      if (canEdit)
                        _buildContextMenuOption(
                          dialogContext,
                          'Edit',
                          Icons.edit,
                          _MessageAction.edit,
                        ),
                      if (canSave)
                        _buildContextMenuOption(
                          dialogContext,
                          'Save to device',
                          Icons.save_alt,
                          _MessageAction.saveImage,
                        ),
                      if (canDelete)
                        _buildContextMenuOption(
                          dialogContext,
                          'Delete',
                          Icons.delete,
                          _MessageAction.delete,
                          textColor: Colors.redAccent,
                        ),
                      if (canRemovePlaceholder)
                        _buildContextMenuOption(
                          dialogContext,
                          'Remove from chat',
                          Icons.delete_forever,
                          _MessageAction.removeDeleted,
                          textColor: Colors.redAccent,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (action == null) return;

    switch (action) {
      case _MessageAction.copy:
        _copyMessageText(message.text);
        break;
      case _MessageAction.edit:
        if (!hasText) break;
        _startEditingMessage(message);
        break;
      case _MessageAction.saveImage:
        if (!hasImage || message.imageUrl == null) break;
        await _saveImageToGallery(message.imageUrl!);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case _MessageAction.removeDeleted:
        await _deleteMessage(message, removeFromScreen: true);
        break;
    }
  }

  void _copyMessageText(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  void _startEditingMessage(ChatMessageModel message) {
    setState(() => _editingMessageId = message.messageId);
    _controller.text = message.text;
    _controller.selection =
        TextSelection.collapsed(offset: message.text.length);
    _textFocusNode.requestFocus();
  }

  void _cancelEditing() {
    if (!mounted) return;
    setState(() => _editingMessageId = null);
    _controller.clear();
    _textFocusNode.unfocus();
  }


  Future<void> _saveImageToGallery(String url) async {
    if (kIsWeb) {
      if (!mounted) return;
      return;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image');
      }
      await ImageGallerySaver.saveImage(
        response.bodyBytes,
        quality: 90,
        name: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _deleteMessage(
    ChatMessageModel message, {
    bool removeFromScreen = false,
  }) async {
    try {
      await _chatService.deleteMessage(
        widget.chatId,
        message,
        userId: _auth.userId,
        removeFromScreen: removeFromScreen,
      );
    } catch (_) {
      if (!mounted) return;
    }
  }

  Widget _buildContextMenuOption(
    BuildContext context,
    String label,
    IconData icon,
    _MessageAction action, {
    Color? textColor,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(action),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              icon,
              color: textColor ?? _tealAccent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor ?? _profileTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_selectedImageBytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _selectedImageBytes!,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: _clearSelectedImage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Widget _buildMessageRow(
    BuildContext context,
    ChatMessageModel message,
    bool isMe,
    String currentUserId,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Builder(
          builder: (bubbleContext) => GestureDetector(
            onLongPress: () => _showMessageActions(
              bubbleContext,
              message,
              isMe,
              currentUserId,
            ),
            child: IntrinsicWidth(
              stepWidth: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? _bubbleMe : _bubbleYou,
                    borderRadius: BorderRadius.circular(_containerRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _buildBubbleContent(
                    context,
                    message,
                    isMe,
                    currentUserId,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.userId;

    final canSend = _controller.text.trim().isNotEmpty || _selectedImage != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _profileTextColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                FutureBuilder<String?>(
                  future: _photoFuture,
                  builder: (context, snapshot) {
                    return DefaultProfileAvatar(
                      radius: 18,
                      photoUrl: snapshot.data,
                      label: widget.otherUserName,
                    );
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.otherUserName,
                    style: const TextStyle(
                      color: _profileTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          actions: widget.hideCallAction
              ? null
              : [
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: () {},
                    icon: const Icon(
                      Icons.call,
                      color: _profileTextColor,
                      size: 20,
                    ),
                  ),
                ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StreamBuilder<List<ChatMessageModel>>(
                stream: _chatService.streamMessages(widget.chatId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snap.data!;
                  _maybeMarkMessagesRead(messages, userId);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(),
                  );

                  final visibleMessages = messages
                      .where((msg) => !msg.hiddenFor.contains(userId))
                      .toList();

                  return Column(
                    children: [
                      if (visibleMessages.isNotEmpty)
                        _buildDateHeader(visibleMessages),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 12, bottom: 16),
                          itemCount: visibleMessages.length,
                          itemBuilder: (context, index) {
                            final message = visibleMessages[index];
                            final isMe = message.senderId == userId;
                            return _buildMessageRow(
                              context,
                              message,
                              isMe,
                              userId,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_selectedImage != null) _buildImagePreview(),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: _tealAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit,
                      color: _tealAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing message',
                        style: TextStyle(
                          color: _tealAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelEditing,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: _tealAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: _profileBorderColor),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _openGallery,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.add,
                      color: Colors.grey.shade700,
                      size: 20,
                    ),
                  ),
                  Expanded(
                  child: TextField(
                    focusNode: _textFocusNode,
                    controller: _controller,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: _profileTextColor,
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Type something...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _openCamera,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.photo_camera,
                      color: Colors.grey.shade700,
                      size: 20,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: canSend && !_isUploadingImage
                          ? _tealAccent
                          : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: const EdgeInsets.all(4),
                      onPressed: canSend && !_isUploadingImage
                          ? _handleSend
                          : null,
                      icon: _isUploadingImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
