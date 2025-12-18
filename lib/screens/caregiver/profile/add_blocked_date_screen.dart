import 'package:flutter/material.dart';

import '../../../ui_tokens.dart';
import 'profile_availability_shared.dart';

const Color _profileDarkText = UiTokens.textDark;
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _profileTealAccent = UiTokens.teal;
const Color _profileGoldAccent = UiTokens.gold;

const BorderRadius _profilePrimaryBorderRadius = BorderRadius.all(
  Radius.circular(UiTokens.r18),
);
const BorderRadius _profileSecondaryBorderRadius = BorderRadius.all(
  Radius.circular(UiTokens.r14),
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
const TextStyle _profileOutlinedButtonTextStyle = TextStyle(
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w700,
);
const TextStyle _profileElevatedButtonTextStyle = TextStyle(
  fontSize: UiTokens.fs14,
  fontWeight: FontWeight.w600,
);
const TextStyle _profileHelperLabelStyle = TextStyle(
  color: _profileDarkText60,
  fontSize: UiTokens.fs12,
  fontWeight: FontWeight.w600,
);

class AddBlockedDateScreen extends StatefulWidget {
  const AddBlockedDateScreen({super.key, required this.onSave});

  final Future<void> Function(BlockedDate entry) onSave;

  @override
  State<AddBlockedDateScreen> createState() => _AddBlockedDateScreenState();
}

class _AddBlockedDateScreenState extends State<AddBlockedDateScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_markDirty);
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _hasChanges &&
      _startDate != null &&
      _endDate != null &&
      !_endDate!.isBefore(_startDate!);

  Future<void> _handleSave() async {
    if (!_canSave || _isSaving) return;
    setState(() => _isSaving = true);
    final entry = BlockedDate(
      start: _startDate!,
      end: _endDate!,
      description: _descriptionController.text.trim(),
    );
    try {
      await widget.onSave(entry);
      if (!mounted) return;
      setState(() => _hasChanges = false);
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectDate({
    required DateTime initialDate,
    required ValueChanged<DateTime> onSelected,
    required DateTime firstDate,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 200)),
      builder: availabilityPickerBuilder,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  Widget _buildDateButton({
    required String label,
    DateTime? value,
    required VoidCallback onTap,
  }) {
    final display = value == null
        ? 'Select $label date'
        : blockedFullFormat.format(value);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _profileDarkText,
        textStyle: _profileOutlinedButtonTextStyle,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(
          borderRadius: _profileButtonBorderRadiusSmall,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: UiTokens.s8,
          horizontal: UiTokens.s10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _profileHelperLabelStyle),
          const SizedBox(height: UiTokens.s4),
          Text(display, style: _profileBodySemiBoldStyle),
        ],
      ),
    );
  }

  void _markDirty() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
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
          style: TextStyle(
            fontSize: UiTokens.fs16,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'You have unsaved changes. Leave anyway?',
          style: TextStyle(
            fontSize: UiTokens.fs14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
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
          const SizedBox(width: UiTokens.s6),
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
            'Add blocked dates',
            style: _profileAppBarTitleStyle,
          ),
          foregroundColor: _profileDarkText,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: UiTokens.s12,
              vertical: UiTokens.s6,
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
                  UiTokens.s12,
                  UiTokens.s6,
                  UiTokens.s12,
                  UiTokens.s10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'Add blocked dates',
                        style: _profileSectionHeaderStyle,
                      ),
                    ),
                    const SizedBox(height: UiTokens.s4),
                    TextField(
                      controller: _descriptionController,
                      style: _profileBodySemiBoldStyle,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Reason (optional)',
                        hintStyle: _profileHelperLabelStyle,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: _profileSecondaryBorderRadius,
                          borderSide: const BorderSide(
                            color: Color(0xFFE0E0E0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: _profileSecondaryBorderRadius,
                          borderSide: const BorderSide(
                            color: Color(0xFFE0E0E0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: _profileSecondaryBorderRadius,
                          borderSide: const BorderSide(
                            color: Color(0xFFE0E0E0),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: UiTokens.s10,
                          vertical: UiTokens.s10,
                        ),
                      ),
                    ),
                    const SizedBox(height: UiTokens.s4),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateButton(
                            label: 'Start',
                            value: _startDate,
                            onTap: () => _selectDate(
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              onSelected: (picked) {
                                setState(() {
                                  _startDate = picked;
                                  if (_endDate != null &&
                                      _endDate!.isBefore(_startDate!)) {
                                    _endDate = _startDate;
                                  }
                                  _hasChanges = true;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: UiTokens.s6),
                        Expanded(
                          child: _buildDateButton(
                            label: 'End',
                            value: _endDate,
                            onTap: () => _selectDate(
                              initialDate:
                                  _endDate ?? _startDate ?? DateTime.now(),
                              firstDate: _startDate ?? DateTime.now(),
                              onSelected: (picked) {
                                setState(() {
                                  _endDate = picked;
                                  _hasChanges = true;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: UiTokens.s4),
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
