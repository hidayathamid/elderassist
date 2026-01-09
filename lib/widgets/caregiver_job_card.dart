import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_job.dart';
import 'package:emergencies_disability_assistance_app/screens/caregiver/jobs/caregiver_job_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/chat/user_chat_screen.dart';
import 'package:emergencies_disability_assistance_app/services/chat_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_screen.dart';

/// Reusable card that mirrors the card design from the jobs screen.
class CaregiverJobCard extends StatelessWidget {
  const CaregiverJobCard({
    super.key,
    required this.job,
    required this.onView,
    this.onTrack,
    this.matchHomeStyle = false,
  });

  final CaregiverJob job;
  final VoidCallback onView;
  final VoidCallback? onTrack;
  final bool matchHomeStyle;

  int _alphaFromOpacity(double opacity) {
    final value = (opacity * 255).round();
    if (value < 0) return 0;
    if (value > 255) return 255;
    return value;
  }

  String get _timeLabel {
    final time = job.time.trim();
    return time.isNotEmpty ? time : 'Time pending';
  }

  Future<void> _dialNumber(BuildContext context, String? phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = (phone ?? '').trim();
    if (trimmed.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Phone number is not available.')),
      );
      return;
    }
    final telUri = Uri(scheme: 'tel', path: trimmed);
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to place the call.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to place the call.')),
      );
    }
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openChat(BuildContext context) async {
    final userId = job.userId.trim();
    if (userId.isEmpty) {
      _notify(context, 'Client not attached yet');
      return;
    }
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.isEmpty) {
      _notify(context, 'Please sign in to chat');
      return;
    }
    final chatService = ChatService();
    final chatId = await chatService.createOrGetChat(
      userId,
      caregiverId,
      personId: job.personId,
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (chatId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open chat')),
      );
      return;
    }
    if (!context.mounted) return;
    final personName = job.personName.isNotEmpty ? job.personName : 'Client';
    await chatService.setChatLabel(chatId, personName);
    await chatService.setChatPersonInfo(
      chatId,
      personId: job.personId,
      personName: personName,
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) => UserChatScreen(
          chatId: chatId,
          otherUserId: userId,
          otherUserName: personName,
          hideCallAction: true,
        ),
      ),
    );
  }

  void _openCaregiverDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverJobDetailsScreen(bookingId: job.bookingId),
      ),
    );
  }

  List<_ActionConfig> _actionButtons(BuildContext context, String? phone) {
    final normalizedStatus = job.status.trim().toUpperCase();
    final isCancelled =
        normalizedStatus == 'CANCELLED' ||
        normalizedStatus == 'CANCELED' ||
        normalizedStatus == 'COMPLETED';
    final isUpcomingStatus =
        normalizedStatus == 'SCHEDULED' || normalizedStatus == 'PENDING';
    if (isCancelled) {
      return [
        _ActionConfig(
          label: 'View Details',
          icon: Icons.info_outline,
          onPressed: onView,
        ),
      ];
    }

    final actions = <_ActionConfig>[];
    if (!isUpcomingStatus) {
      actions.add(
        _ActionConfig(
          label: 'Track',
          icon: Icons.navigation_outlined,
          onPressed: () {
            if (onTrack != null) {
              onTrack!();
            } else {
              _openCaregiverDetails(context);
            }
          },
          gradient: const LinearGradient(
            colors: [activityAccentBlue, activityAccentBlue],
          ),
          tone: _PillTone.teal,
        ),
      );
    }
    actions.add(
      _ActionConfig(
        label: 'View',
        icon: Icons.info_outline,
        onPressed: onView,
        tone: _PillTone.outline,
      ),
    );
    actions.addAll([
      _ActionConfig(
        label: 'Call',
        icon: Icons.phone,
        kind: _ActionButtonKind.circle,
        onPressed: phone?.trim().isNotEmpty == true
            ? () => _dialNumber(context, phone)
            : null,
      ),
      _ActionConfig(
        label: 'Chat',
        icon: Icons.chat_bubble_outline,
        kind: _ActionButtonKind.circle,
        onPressed: () => _openChat(context),
      ),
    ]);
    return actions;
  }

  Widget _buildActionRow(List<_ActionConfig> actions) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final pillActions = actions
        .where((action) => action.kind == _ActionButtonKind.pill)
        .toList();
    final circleActions = actions
        .where((action) => action.kind == _ActionButtonKind.circle)
        .toList();

    return Row(
      children: [
        for (var i = 0; i < pillActions.length; i++) ...[
          Expanded(child: _PillActionButton(action: pillActions[i])),
          if (i != pillActions.length - 1) const SizedBox(width: 8),
        ],
        if (circleActions.isNotEmpty) ...[
          if (pillActions.isNotEmpty) const SizedBox(width: 8),
          for (var i = 0; i < circleActions.length; i++) ...[
            if (i != 0) const SizedBox(width: 6),
            _CircleActionButton(action: circleActions[i]),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceLabel = job.service.isNotEmpty ? job.service : 'Home care';
    final locationLabel = job.location.isNotEmpty
        ? job.location
        : 'Location pending';
    final dateLabel = job.scheduledDate.isNotEmpty
        ? job.scheduledDate
        : 'Date pending';
    final personName =
        job.personName.isNotEmpty ? job.personName : 'Selected person';
    final personAddress =
        job.personAddress.isNotEmpty ? job.personAddress : locationLabel;
    final normalizedStatus = job.status.trim().toUpperCase();
    final isCancelledStatus =
        normalizedStatus == 'CANCELLED' || normalizedStatus == 'CANCELED';
    final cancellationReason = isCancelledStatus
        ? job.cancellationReason.trim()
        : '';

    final userFuture = job.userId.isNotEmpty
        ? FirebaseFirestore.instance.collection('users').doc(job.userId).get()
        : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: userFuture,
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? const <String, dynamic>{};
        final userName = (userData['name'] as String?)?.trim() ?? 'Client';
        final userPhoto = (userData['photoUrl'] as String?)?.trim();
        final hasPhoto = userPhoto?.isNotEmpty == true;
        final phone = (userData['phone'] as String?)?.trim();
        final actions = _actionButtons(context, phone);
        final personLabelFromUser = resolvePersonLabel(userData, job);
        final personLabel =
            personLabelFromUser ??
            (job.personLabel.isNotEmpty ? job.personLabel : null);

        if (!matchHomeStyle) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: _caregiverCardRadius,
              border: Border.all(color: _caregiverCardBorderColor),
              boxShadow: [_caregiverCardShadow],
            ),
            clipBehavior: Clip.hardEdge,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.grey[200],
                        child: ClipOval(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: Text(
                                    userName.isNotEmpty
                                        ? userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                if (hasPhoto)
                                  SafeNetworkImage(
                                    userPhoto!.trim(),
                                    fit: BoxFit.cover,
                                    placeholder: const SizedBox.shrink(),
                                    errorWidget: const SizedBox.shrink(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: activityPrimaryTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              serviceLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [_StatusChip(status: job.status)],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        size: 12,
                        color: activityPrimaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: activityPrimaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: activityPrimaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _timeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: activityPrimaryTextColor,
                        ),
                      ),
                      if (isCancelledStatus && cancellationReason.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Reason: $cancellationReason',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        DefaultProfileAvatar(
                          radius: 14,
                          photoUrl: userPhoto?.trim().isNotEmpty == true
                              ? userPhoto!.trim()
                              : null,
                          label: personName,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                personName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                              if (personLabel?.isNotEmpty == true) ...[
                                const SizedBox(height: 2),
                                Text(
                                  personLabel!,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                personAddress,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (job.notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        job.notes,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 0),
                  const SizedBox(height: 12),
                  _buildActionRow(actions),
                ],
              ),
            ),
          );
        }

        final metaColor = activityPrimaryTextColor.withAlpha(
          _alphaFromOpacity(0.6),
        );
        final trimmedPersonTag = personLabel?.trim();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD7DCE3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.1)),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFEEF1F4)),
                      ),
                      child: ClipOval(
                        child: hasPhoto
                            ? SafeNetworkImage(
                                userPhoto!.trim(),
                                fit: BoxFit.cover,
                                placeholder: const Icon(
                                  Icons.person,
                                  color: Colors.grey,
                                ),
                                errorWidget: const Icon(
                                  Icons.person,
                                  color: Colors.grey,
                                ),
                              )
                            : const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  userName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: activityPrimaryTextColor,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _StatusChip(status: job.status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 20,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  ServiceTagChip(label: serviceLabel),
                                  if (trimmedPersonTag?.isNotEmpty == true) ...[
                                    const SizedBox(width: 4),
                                    ServiceTagChip(label: trimmedPersonTag!),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.calendar_month, size: 13, color: metaColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  dateLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: metaColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.access_time, size: 13, color: metaColor),
                              const SizedBox(width: 4),
                              Text(
                                _timeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: metaColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isCancelledStatus && cancellationReason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Reason: $cancellationReason',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withAlpha(_alphaFromOpacity(0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      DefaultProfileAvatar(
                        radius: 18,
                        photoUrl:
                            userPhoto?.trim().isNotEmpty == true ? userPhoto!.trim() : null,
                        label: personName.isNotEmpty ? personName : userName,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: activityPrimaryTextColor,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (trimmedPersonTag?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                trimmedPersonTag!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              personAddress,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (job.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      job.notes,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 0),
                const SizedBox(height: 12),
                _buildActionRow(actions),
              ],
            ),
          ),
        );
      },
    );
  }
}

const BorderRadius _caregiverCardRadius = BorderRadius.all(Radius.circular(18));
const Color _caregiverCardBorderColor = Color(0xFFD7DCE3);
const BoxShadow _caregiverCardShadow = BoxShadow(
  color: Color(0x1A000000),
  blurRadius: 20,
  offset: Offset(0, 10),
);
final BoxShadow _statusChipShadow = const BoxShadow(
  color: Color(0x14000000),
  blurRadius: 8,
  offset: Offset(0, 4),
);
const double _pillButtonHeight = 34.0;
const double _circleButtonSize = 40.0;

enum _ActionButtonKind { pill, circle }

enum _PillTone { outline, teal, yellow }

class _ActionConfig {
  const _ActionConfig({
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = _PillTone.outline,
    this.kind = _ActionButtonKind.pill,
    this.gradient,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final _PillTone tone;
  final _ActionButtonKind kind;
  final Gradient? gradient;
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    final isEnabled = action.onPressed != null;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (action.icon != null) ...[
          Icon(
            action.icon,
            size: 16,
            color: action.tone == _PillTone.teal
                ? (isEnabled ? Colors.white : Colors.white70)
                : action.tone == _PillTone.yellow
                    ? (isEnabled ? Colors.black87 : Colors.black45)
                    : (isEnabled ? Colors.black87 : Colors.black38),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: action.tone == _PillTone.teal
                  ? (isEnabled ? Colors.white : Colors.white70)
                  : action.tone == _PillTone.yellow
                      ? (isEnabled ? Colors.black87 : Colors.black45)
                      : (isEnabled ? Colors.black87 : Colors.black38),
            ),
          ),
        ),
      ],
    );

    if (action.tone == _PillTone.outline) {
      return SizedBox(
        height: _pillButtonHeight,
        child: OutlinedButton(
          onPressed: isEnabled ? action.onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: radius),
            minimumSize: const Size(0, _pillButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: child,
        ),
      );
    }

    if (action.gradient != null) {
      return SizedBox(
        height: _pillButtonHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: action.gradient,
            borderRadius: radius,
          ),
          child: ElevatedButton(
            onPressed: isEnabled ? action.onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: radius),
              minimumSize: const Size(0, _pillButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shadowColor: Colors.transparent,
            ),
            child: child,
          ),
        ),
      );
    }

    final accent = action.tone == _PillTone.yellow
        ? activityButtonYellow
        : activityAccentBlue;
    final foreground = action.tone == _PillTone.yellow
        ? Colors.black87
        : Colors.white;
    return SizedBox(
      height: _pillButtonHeight,
      child: ElevatedButton(
        onPressed: isEnabled ? action.onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(borderRadius: radius),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadowColor: const Color(0x33000000),
        ),
        child: child,
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    final isEnabled = action.onPressed != null;
    return SizedBox(
      width: _circleButtonSize,
      height: _circleButtonSize,
      child: OutlinedButton(
        onPressed: isEnabled ? action.onPressed : null,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          side: BorderSide(color: Colors.grey.shade300),
          backgroundColor: Colors.white,
          minimumSize: const Size(_circleButtonSize, _circleButtonSize),
        ),
        child: Icon(
          action.icon ?? Icons.chat_bubble_outline,
          size: 18,
          color: isEnabled ? Colors.black54 : Colors.black26,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  String get _normalized => status.trim().toLowerCase();

  Color get _dotColor {
    return switch (_normalized) {
      'ongoing' || 'in_progress' => Colors.blue.shade700,
      'completed' || 'assigned' => Colors.green.shade700,
      'cancelled' => Colors.red.shade700,
      _ => Colors.grey.shade600,
    };
  }

  String get _label {
    return switch (_normalized) {
      'ongoing' || 'in_progress' => 'Ongoing',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => _formatLabel(status),
    };
  }

  String _formatLabel(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) return 'Scheduled';
    final segments = normalized
        .split(RegExp(r'[\s_-]+'))
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
              segment[0].toUpperCase() +
              (segment.length > 1 ? segment.substring(1).toLowerCase() : ''),
        )
        .toList();
    return segments.isEmpty ? 'Scheduled' : segments.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _caregiverCardBorderColor),
        boxShadow: [_statusChipShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
