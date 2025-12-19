import 'package:flutter/material.dart';

const double _caregiverCardRadius = 18.0;
final Color _caregiverCardBorderColor = Colors.grey.shade300;
final BoxShadow _caregiverCardShadow = const BoxShadow(
  color: Color(0x14000000),
  blurRadius: 16,
  offset: Offset(0, 6),
);

enum ActionButtonKind { pill, circle }

enum PillTone { outline, teal, yellow }

class ActionConfig {
  const ActionConfig({
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = PillTone.outline,
    this.kind = ActionButtonKind.pill,
    this.gradient,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PillTone tone;
  final ActionButtonKind kind;
  final Gradient? gradient;
}

class CaregiverJobCard extends StatelessWidget {
  const CaregiverJobCard({
    required this.clientName,
    required this.serviceLabel,
    required this.priceLabel,
    required this.status,
    required this.timeLabel,
    required this.dateLabel,
    required this.locationLabel,
    required this.notes,
    required this.actions,
    this.avatarLabel,
    this.avatarPhotoUrl,
    this.onTap,
  });

  final String clientName;
  final String serviceLabel;
  final String priceLabel;
  final String status;
  final String timeLabel;
  final String dateLabel;
  final String locationLabel;
  final String notes;
  final List<ActionConfig> actions;
  final String? avatarLabel;
  final String? avatarPhotoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pillActions =
        actions.where((action) => action.kind == ActionButtonKind.pill).toList();
    final circleActions =
        actions.where((action) => action.kind == ActionButtonKind.circle).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_caregiverCardRadius),
        border: Border.all(color: _caregiverCardBorderColor),
        boxShadow: [_caregiverCardShadow],
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_caregiverCardRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: avatarPhotoUrl != null && avatarPhotoUrl!.isNotEmpty
                          ? NetworkImage(avatarPhotoUrl!)
                          : null,
                      child: avatarPhotoUrl == null || avatarPhotoUrl!.isEmpty
                          ? Text(
                              avatarLabel?.isNotEmpty == true
                                  ? avatarLabel![0].toUpperCase()
                                  : clientName.isNotEmpty
                                      ? clientName[0].toUpperCase()
                                      : '?',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clientName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Color(0xFF1B1D29),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serviceLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          priceLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF1B1D29),
                          ),
                        ),
                        const SizedBox(height: 4),
                        StatusBadge(status: status),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.black54),
                    const SizedBox(width: 6),
                    Text(
                      timeLabel.isNotEmpty ? timeLabel : 'Time pending',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.calendar_today, size: 14, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateLabel.isNotEmpty ? dateLabel : 'Date pending',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locationLabel.isNotEmpty ? locationLabel : 'Location pending',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    notes,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildActionRow(pillActions, circleActions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(
    List<ActionConfig> pillActions,
    List<ActionConfig> circleActions,
  ) {
    final pillChildren = <Widget>[];
    for (var i = 0; i < pillActions.length; i++) {
      pillChildren.add(Expanded(child: _PillActionButton(action: pillActions[i])));
      if (i != pillActions.length - 1) pillChildren.add(const SizedBox(width: 8));
    }
    final circleChildren = <Widget>[];
    for (var i = 0; i < circleActions.length; i++) {
      if (i != 0) circleChildren.add(const SizedBox(width: 6));
      circleChildren.add(_CircleActionButton(action: circleActions[i]));
    }

    return Row(
      children: [
        if (pillChildren.isNotEmpty) ...pillChildren,
        if (circleChildren.isNotEmpty) ...[
          if (pillChildren.isNotEmpty) const SizedBox(width: 8),
          ...circleChildren,
        ],
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status});

  final String status;

  Color get _indicatorColor {
    final normalized = status.trim().toLowerCase();
    if (normalized.contains('ongoing') || normalized.contains('in_progress')) {
      return Colors.blue.shade700;
    }
    if (normalized.contains('assigned') ||
        normalized.contains('ready') ||
        normalized.contains('scheduled')) {
      return const Color(0xFF00A8A7);
    }
    if (normalized.contains('completed')) {
      return Colors.green.shade700;
    }
    if (normalized.contains('cancelled') || normalized.contains('canceled')) {
      return Colors.red.shade700;
    }
    return Colors.grey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _indicatorColor.withAlpha(40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _indicatorColor.withAlpha(150)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _indicatorColor,
        ),
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.action});

  final ActionConfig action;

  @override
  Widget build(BuildContext context) {
    final isEnabled = action.onPressed != null;
    final color = action.tone == PillTone.teal
        ? (isEnabled ? Colors.white : Colors.white70)
        : action.tone == PillTone.yellow
            ? (isEnabled ? Colors.black87 : Colors.black45)
            : (isEnabled ? Colors.black87 : Colors.black38);
    final gradient = action.gradient;
    final backgroundColor = action.tone == PillTone.teal
        ? (isEnabled ? const Color(0xFF00A8A7) : const Color(0xFF00A8A7).withAlpha(150))
        : action.tone == PillTone.yellow
            ? (isEnabled ? const Color(0xFFF7CE46) : const Color(0xFFF7CE46).withAlpha(150))
            : Colors.white;

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (action.icon != null) ...[
          Icon(action.icon, size: 16, color: color),
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
              color: color,
            ),
          ),
        ),
      ],
    );

    final buttonChild = gradient != null
        ? DecoratedBox(
            decoration:
                BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(22)),
            child: ElevatedButton(
              onPressed: isEnabled ? action.onPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shadowColor: Colors.transparent,
              ),
              child: child,
            ),
          )
        : ElevatedButton(
            onPressed: isEnabled ? action.onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shadowColor: const Color(0x33000000),
            ),
            child: child,
          );

    return SizedBox(height: 34, child: buttonChild);
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.action});

  final ActionConfig action;

  @override
  Widget build(BuildContext context) {
    final isEnabled = action.onPressed != null;
    return SizedBox(
      width: 40,
      height: 40,
      child: OutlinedButton(
        onPressed: isEnabled ? action.onPressed : null,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          side: BorderSide(color: Colors.grey.shade300),
          backgroundColor: Colors.white,
          minimumSize: const Size(40, 40),
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
