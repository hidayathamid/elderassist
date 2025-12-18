import 'package:flutter/material.dart';

import '../../../ui_tokens.dart';
import 'profile_availability_shared.dart';

const Color _profileDarkText = UiTokens.textDark;
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _profileDarkText85 = Color(0xD91B1D29);
const Color _profileTealAccent = UiTokens.teal;
const Color _profileGoldAccent = UiTokens.gold;

const BorderRadius _profilePrimaryBorderRadius = BorderRadius.all(
  Radius.circular(UiTokens.r18),
);
const BorderRadius _profileSecondaryBorderRadius = BorderRadius.all(
  Radius.circular(UiTokens.r16),
);
const BorderRadius _profileHandleBorderRadius = BorderRadius.all(
  Radius.circular(UiTokens.r12),
);
const BorderRadius _profileButtonBorderRadiusLarge = BorderRadius.all(
  Radius.circular(UiTokens.r18),
);
const BorderRadius _profileButtonBorderRadiusSmall = BorderRadius.all(
  Radius.circular(UiTokens.r14),
);

const List<BoxShadow> _profilePrimaryCardShadow = [
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.08),
    blurRadius: 16,
    offset: Offset(0, 6),
  ),
];
const List<BoxShadow> _profileSecondaryCardShadow = [
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.04),
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

const TextStyle _profileAppBarTitleStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs18,
  fontWeight: FontWeight.w600,
);

const TextStyle _profileSectionHeaderStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs15,
  fontWeight: FontWeight.w700,
);

const TextStyle _profileBodySemiBoldStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w600,
);

const TextStyle _profileDayLabelStyle = TextStyle(
  color: _profileDarkText85,
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w700,
);

const TextStyle _profileHelperLabelStyle = TextStyle(
  color: _profileDarkText60,
  fontSize: UiTokens.fs12,
  fontWeight: FontWeight.w600,
);

const TextStyle _profileDialogTitleStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs16,
  fontWeight: FontWeight.w700,
);

const TextStyle _profileDialogContentStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w600,
);

const TextStyle _profileElevatedButtonTextStyle = TextStyle(
  color: _profileDarkText,
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w600,
);

class RescheduleBookingScreen extends StatefulWidget {
  const RescheduleBookingScreen({
    super.key,
    required this.initialSchedule,
    required this.onSave,
  });

  final List<DaySchedule> initialSchedule;
  final Future<void> Function(List<DaySchedule>) onSave;

  @override
  State<RescheduleBookingScreen> createState() =>
      _RescheduleBookingScreenState();
}

class _RescheduleBookingScreenState extends State<RescheduleBookingScreen> {
  late List<DaySchedule> _drafts;
  bool _isSaving = false;
  bool _hasChanges = false;

  bool get _canSave =>
      _hasChanges &&
      !_drafts.any(
        (entry) =>
            entry.available && (entry.start.isEmpty || entry.end.isEmpty),
      );

  @override
  void initState() {
    super.initState();
    _drafts = widget.initialSchedule.map((entry) => entry.copyWith()).toList();
  }

  Future<void> _handleSave() async {
    if (!_canSave || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_drafts);
      if (!mounted) return;
      setState(() => _hasChanges = false);
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r14),
        ),
        title: const Text(
          'Discard changes?',
          style: _profileDialogTitleStyle,
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'You have unsaved changes. Leave anyway?',
          style: _profileDialogContentStyle,
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: UiTokens.s12),
        actions: [
          SizedBox(
            width: 120,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(UiTokens.r14),
                ),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(
                  vertical: UiTokens.buttonVPad,
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: _profileDarkText,
                  fontWeight: FontWeight.w700,
                  fontSize: UiTokens.fs14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _profileGoldAccent,
                foregroundColor: _profileDarkText,
                padding: const EdgeInsets.symmetric(
                  vertical: UiTokens.buttonVPad,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(UiTokens.r14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: UiTokens.fs14,
                  color: _profileDarkText,
                ),
              ),
              child: const Text('Discard'),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) {
      Navigator.of(context).pop();
    }
    return shouldLeave;
  }

  ButtonStyle _saveButtonStyle(bool hasChanges) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return hasChanges
              ? _profileGoldAccent.withValues(alpha: 0.8)
              : const Color(0xFFE0E0E0);
        }
        return _profileGoldAccent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return hasChanges ? const Color(0xFF1B1D29) : const Color(0xFF707070);
        }
        return _profileDarkText;
      }),
      elevation: WidgetStateProperty.resolveWith<double>(
        (states) => states.contains(WidgetState.disabled) ? 0 : 2,
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: UiTokens.s12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: _profileButtonBorderRadiusLarge),
      ),
      textStyle: WidgetStateProperty.all(_profileElevatedButtonTextStyle),
    );
  }

  TimeOfDay _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${twoDigit(time.hour)}:${twoDigit(time.minute)}';
  }

  Widget _buildRow(int index) {
    final entry = _drafts[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: UiTokens.s6),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s10,
          vertical: UiTokens.s6,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: _profileSecondaryBorderRadius,
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: _profileSecondaryCardShadow,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(entry.day, style: _profileDayLabelStyle),
                const Spacer(),
                Switch(
                  value: entry.available,
                  trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _profileTealAccent.withValues(alpha: 0.25);
                    }
                    return const Color(0xFFE0E0E0);
                  }),
                  thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return const Color(0xFFBDBDBD);
                  }),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) {
                    setState(() {
                      final defaultEntry = defaultScheduleLookup[entry.day];
                      _drafts[index] = entry.copyWith(
                        available: value,
                        start: value
                            ? entry.start.isEmpty
                                  ? defaultEntry?.start ?? '08:00'
                                  : entry.start
                            : '',
                        end: value
                            ? entry.end.isEmpty
                                  ? defaultEntry?.end ?? '18:00'
                                  : entry.end
                            : '',
                      );
                      _hasChanges = true;
                    });
                  },
                ),
              ],
            ),
            if (entry.available) ...[
              const SizedBox(height: UiTokens.s2),
              Row(
                children: [
                  Expanded(
                    child: TimePickerChip(
                      label: 'Start',
                      value: entry.start,
                      labelStyle: _profileHelperLabelStyle,
                      valueStyle: _profileBodySemiBoldStyle,
                      onTap: () async {
                        final selected = await showTimePicker(
                          context: context,
                          initialTime: _parseTimeOfDay(entry.start),
                          builder: availabilityPickerBuilder,
                        );
                        if (selected != null) {
                          setState(() {
                            _drafts[index] = _drafts[index].copyWith(
                              start: _formatTimeOfDay(selected),
                            );
                            _hasChanges = true;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: UiTokens.s8),
                  Expanded(
                    child: TimePickerChip(
                      label: 'End',
                      value: entry.end,
                      labelStyle: _profileHelperLabelStyle,
                      valueStyle: _profileBodySemiBoldStyle,
                      onTap: () async {
                        final selected = await showTimePicker(
                          context: context,
                          initialTime: _parseTimeOfDay(entry.end),
                          builder: availabilityPickerBuilder,
                        );
                        if (selected != null) {
                          setState(() {
                            _drafts[index] = _drafts[index].copyWith(
                              end: _formatTimeOfDay(selected),
                            );
                            _hasChanges = true;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackPress,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.08),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          leading: IconButton(
            onPressed: _handleBackPress,
            iconSize: UiTokens.icon20,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileDarkText,
              size: UiTokens.icon20,
            ),
          ),
          title: const Text(
            'Edit weekly schedule',
            style: _profileAppBarTitleStyle,
          ),
          foregroundColor: _profileDarkText,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: UiTokens.s10,
              vertical: UiTokens.s4,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: _profilePrimaryBorderRadius,
                border: Border.all(color: const Color(0xFFE0E0E0)),
                boxShadow: _profilePrimaryCardShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  UiTokens.s10,
                  UiTokens.s4,
                  UiTokens.s10,
                  UiTokens.s8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'Edit weekly schedule',
                        style: _profileSectionHeaderStyle,
                      ),
                    ),
                    const SizedBox(height: UiTokens.s2),
                    Column(
                      children: List.generate(
                        _drafts.length,
                        (index) => _buildRow(index),
                      ),
                    ),
                    const SizedBox(height: UiTokens.s2),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_canSave && !_isSaving)
                            ? _handleSave
                            : null,
                        style: _saveButtonStyle(_hasChanges),
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _profileDarkText,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: _profileBodySemiBoldStyle,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
