import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'dart:async';

const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _dialogBackground = Color(0xFFF7F8FA);
const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);
const TextStyle _fieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);

class ProfilePhoneEditResult {
  const ProfilePhoneEditResult({
    required this.dialCode,
    required this.countryCode,
    required this.nationalNumber,
  });

  final String dialCode;
  final String countryCode;
  final String nationalNumber;
}

class ProfilePhoneEditScreen extends StatefulWidget {
  const ProfilePhoneEditScreen({
    super.key,
    required this.initialDialCode,
    required this.initialCountryCode,
    required this.initialNationalNumber,
    required this.isCaregiver,
  });

  final String initialDialCode;
  final String initialCountryCode;
  final String initialNationalNumber;
  final bool isCaregiver;

  @override
  State<ProfilePhoneEditScreen> createState() => _ProfilePhoneEditScreenState();
}

class _ProfilePhoneEditScreenState extends State<ProfilePhoneEditScreen> {
  final TextEditingController _currentPhoneController = TextEditingController();
  final TextEditingController _newPhoneDisplayController =
      TextEditingController();
  final TextEditingController _newPhoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String _selectedDialCode = '+60';
  String _currentCountryCode = 'MY';
  String _newFullPhoneNumber = '';
  String _newNationalNumber = '';

  String? _verificationId;
  int? _resendToken;

  bool _sendingOtp = false;
  bool _saving = false;

  String? _phoneError;
  String? _otpError;
  String? _phoneMessage;
  Color _phoneMessageColor = Colors.black54;
  bool _phoneHasError = false;
  bool _otpSent = false;
  int _otpCooldownSeconds = 0;
  Timer? _otpCooldownTimer;

  @override
  void initState() {
    super.initState();
    _selectedDialCode = _normalizeDialCode(widget.initialDialCode);
    _currentCountryCode = widget.initialCountryCode.trim().isNotEmpty
        ? widget.initialCountryCode.trim()
        : 'MY';

    final initialFull = _collapseRepeatedDialPrefix(
      widget.initialNationalNumber.trim().isNotEmpty
          ? '$_selectedDialCode${_stripDialCode(widget.initialNationalNumber, _selectedDialCode)}'
          : '',
      _selectedDialCode,
    );
    _currentPhoneController.text = initialFull.trim().isNotEmpty ? initialFull : '-';
    _phoneMessage = 'We\'ll send a verification code via SMS.';
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _currentPhoneController.dispose();
    _newPhoneDisplayController.dispose();
    _newPhoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _normalizeDialCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '+60';
    return trimmed.startsWith('+') ? trimmed : '+$trimmed';
  }

  String _stripDialCode(String phone, String dialCode) {
    final trimmed = phone.trim();
    final normalizedDial = _normalizeDialCode(dialCode);
    if (trimmed.startsWith(normalizedDial)) {
      return trimmed
          .substring(normalizedDial.length)
          .replaceAll(RegExp(r'^\s+'), '');
    }
    return trimmed;
  }

  String _collapseRepeatedDialPrefix(String full, String dialCode) {
    final normalizedDial = _normalizeDialCode(dialCode);
    var value = full.trim();
    while (value.startsWith('$normalizedDial$normalizedDial')) {
      value = value.substring(normalizedDial.length);
    }
    return value;
  }

  void _startOtpCooldown([int seconds = 30]) {
    _otpCooldownTimer?.cancel();
    setState(() => _otpCooldownSeconds = seconds);
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _otpCooldownSeconds = 0);
        return;
      }
      setState(() => _otpCooldownSeconds -= 1);
    });
  }

  Future<void> _showProfileStyleMessageDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: _dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: _dialogContentStyle,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  bool get _otpStage =>
      _otpSent || (_verificationId ?? '').trim().isNotEmpty;

  bool get _isBusy => _sendingOtp || _saving;

  bool get _canSendOtp =>
      !_isBusy &&
      _otpCooldownSeconds == 0 &&
      !_otpStage &&
      _newFullPhoneNumber.trim().isNotEmpty;

  bool get _canSave =>
      !_isBusy && _otpStage && _otpController.text.trim().length == 6;

  Future<bool> _ensurePhoneAvailable() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final phone = _newFullPhoneNumber.trim();
    if (uid.trim().isEmpty || phone.isEmpty) return false;

    Future<bool> existsInCollection(String collection) async {
      final query = await FirebaseFirestore.instance
          .collection(collection)
          .where('phone', isEqualTo: phone)
          .limit(3)
          .get();
      return query.docs.any((d) => d.id != uid);
    }

    try {
      final exists =
          await existsInCollection('users') ||
          await existsInCollection('caregivers') ||
          await existsInCollection('waitinglist');
      if (exists) {
        setState(() {
          _phoneHasError = true;
          _phoneMessage =
              'This number is already registered in the system. Please use another number.';
          _phoneMessageColor = Colors.red;
          _phoneError = 'Use a different phone number';
          _newPhoneController.clear();
          _newFullPhoneNumber = '';
          _newNationalNumber = '';
        });
        return false;
      }
      return true;
    } catch (_) {
      setState(() {
        _phoneHasError = true;
        _phoneMessage = 'Unable to verify number. Please try again.';
        _phoneMessageColor = Colors.red;
      });
      return false;
    }
  }

  Future<void> _sendOtp() async {
    if (!_canSendOtp) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return;

    final full = _newFullPhoneNumber.trim();
    if (full.isEmpty) {
      setState(() => _phoneError = 'Phone is required');
      return;
    }
    if (_currentPhoneController.text.trim() == full.trim()) {
      await _showProfileStyleMessageDialog(
        title: 'Verification',
        message: 'Please enter a different phone number.',
      );
      return;
    }
    final ok = await _ensurePhoneAvailable();
    if (!ok) return;

    setState(() {
      _phoneError = null;
      _otpError = null;
      _sendingOtp = true;
      _otpSent = false;
      _verificationId = null;
    });

    void finish() {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: full,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (credential) async {
          // Auto-retrieval / instant verification.
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            await user.updatePhoneNumber(credential);

            final ref = FirebaseFirestore.instance
                .collection(widget.isCaregiver ? 'caregivers' : 'users')
                .doc(uid);
            await ref.set({
              'phone': full,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            if (!mounted) return;
            await _showProfileStyleMessageDialog(
              title: 'Success',
              message: 'Phone number verified and updated.',
            );
            if (!mounted) return;
            Navigator.of(context).pop(
              ProfilePhoneEditResult(
                dialCode: _normalizeDialCode(_selectedDialCode),
                countryCode: _currentCountryCode,
                nationalNumber: _newNationalNumber.trim(),
              ),
            );
          } catch (_) {
            if (!mounted) return;
            await _showProfileStyleMessageDialog(
              title: 'Verification',
              message:
                  'Unable to verify automatically. Please enter the OTP code instead.',
            );
          } finally {
            finish();
          }
        },
        verificationFailed: (e) async {
          finish();
          if (!mounted) return;
          final errMsg = e.message ?? '';
          final msg = errMsg.contains('BILLING_NOT_ENABLED')
              ? 'We could not send the code. Please try again.'
              : 'We could not send the verification code. Please try again.';
          setState(() {
            _phoneHasError = true;
            _phoneMessage = '$msg (${e.code})';
            _phoneMessageColor = Colors.red;
            _otpSent = false;
            _verificationId = null;
          });
          if (errMsg.toLowerCase().contains('blocked all requests')) {
            _startOtpCooldown();
            await _showProfileStyleMessageDialog(
              title: 'Too many attempts',
              message:
                  'We blocked requests from this device because of unusual activity. Please try again later.',
            );
          }
        },
        codeSent: (verificationId, resendToken) async {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _otpSent = true;
            _otpController.clear();
            _otpError = null;
            _phoneHasError = false;
            _phoneMessage = 'Verification code sent to $full.';
            _phoneMessageColor = Colors.green;
            _newPhoneDisplayController.text = full;
          });
          finish();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted) return;
          setState(() => _verificationId ??= verificationId);
          finish();
        },
      );
    } on FirebaseAuthException catch (e) {
      finish();
      if (!mounted) return;
      setState(() {
        _phoneHasError = true;
        _phoneMessage = e.message ?? 'Unable to send OTP. Please try again.';
        _phoneMessageColor = Colors.red;
      });
    } catch (_) {
      finish();
      if (!mounted) return;
      setState(() {
        _phoneHasError = true;
        _phoneMessage = 'Unable to send OTP. Please try again.';
        _phoneMessageColor = Colors.red;
      });
    }
  }

  Future<void> _saveVerifiedPhone() async {
    if (!_canSave) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return;

    final verificationId = (_verificationId ?? '').trim();
    if (verificationId.isEmpty) return;

    final full = _newFullPhoneNumber.trim();
    final smsCode = _otpController.text.trim();
    if (smsCode.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit OTP code');
      return;
    }

    setState(() {
      _saving = true;
      _otpError = null;
      _phoneError = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.updatePhoneNumber(credential);

      final ref = FirebaseFirestore.instance
          .collection(widget.isCaregiver ? 'caregivers' : 'users')
          .doc(uid);
      await ref.set({
        'phone': full,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      await _showProfileStyleMessageDialog(
        title: 'Success',
        message: 'Phone number verified and updated.',
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        ProfilePhoneEditResult(
          dialCode: _normalizeDialCode(_selectedDialCode),
          countryCode: _currentCountryCode,
          nationalNumber: _newNationalNumber.trim(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-verification-code' => 'Invalid OTP code. Please try again.',
        'session-expired' =>
          'This OTP session has expired. Please tap Verify again.',
        _ => e.message ?? 'Verification failed. Please try again.',
      };
      await _showProfileStyleMessageDialog(
        title: 'Verification failed',
        message: message,
      );
    } catch (_) {
      if (!mounted) return;
      await _showProfileStyleMessageDialog(
        title: 'Verification failed',
        message: 'Verification failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final hasChanges =
        _newPhoneController.text.trim().isNotEmpty ||
        _otpController.text.trim().isNotEmpty ||
        _otpStage;
    if (!hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Discard changes?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You have unsaved changes. Leave anyway?',
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    backgroundColor: _accentGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) Navigator.of(context).pop();
  }

  InputDecoration _profileFieldDecoration({
    required String hintText,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: _profileDarkText, width: 1.1),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFFE53935), width: 1.1),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFFE53935), width: 1.2),
      ),
      errorText: errorText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = _otpStage ? 'Save' : 'Verify';
    final onPrimary = _otpStage ? _saveVerifiedPhone : _sendOtp;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
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
          leading: IconButton(
            onPressed: _handleBackPress,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileDarkText,
              size: 20,
            ),
          ),
          title: const Text(
            'Edit Phone',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Phone Number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _currentPhoneController,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  style: _fieldTextStyle,
                  decoration: _profileFieldDecoration(hintText: 'Phone Number'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'New Number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 6),
                if (_otpStage)
                  TextField(
                    controller: _newPhoneDisplayController,
                    readOnly: true,
                    enableInteractiveSelection: false,
                    style: _fieldTextStyle,
                    decoration: _profileFieldDecoration(hintText: 'New Number'),
                  )
                else
                  Theme(
                    data: Theme.of(context).copyWith(
                      dialogTheme: DialogThemeData(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    child: IntlPhoneField(
                      controller: _newPhoneController,
                      enabled: !_isBusy,
                      initialCountryCode: _currentCountryCode,
                      disableLengthCheck: true,
                      style: _fieldTextStyle,
                      pickerDialogStyle: PickerDialogStyle(
                        backgroundColor: Colors.white,
                        countryNameStyle: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        countryCodeStyle: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        listTilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        listTileDivider: Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey[200],
                        ),
                        searchFieldPadding:
                            const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        searchFieldInputDecoration: InputDecoration(
                          hintText: 'Search country',
                          hintStyle: const TextStyle(color: Colors.black54),
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.black54),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Colors.black87,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                      decoration: InputDecoration(
                        hintText: '123 4567 890',
                        hintStyle: const TextStyle(color: Colors.black38),
                        errorText: _phoneError,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color:
                                _phoneHasError ? Colors.red : Colors.grey[300]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color:
                                _phoneHasError ? Colors.red : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: _phoneHasError ? Colors.red : _profileDarkText,
                            width: 1.1,
                          ),
                        ),
                      ),
                      onChanged: (phone) {
                        final rawNumber = phone.number.trim();
                        final dialCode = phone.countryCode.trim(); // e.g. +60
                        var national =
                            rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
                        if (phone.countryISOCode.toUpperCase() == 'MY') {
                          national = national.replaceFirst(RegExp(r'^0+'), '');
                        }
                        final normalized = national.isEmpty
                            ? ''
                            : '${dialCode.startsWith('+') ? dialCode : '+$dialCode'}$national';
                        setState(() {
                          _currentCountryCode =
                              phone.countryISOCode.toUpperCase();
                          _selectedDialCode = _normalizeDialCode(dialCode);
                          _newNationalNumber = national;
                          _newFullPhoneNumber = normalized;
                          _newPhoneDisplayController.text = normalized;
                          _phoneHasError = false;
                          _phoneError = null;
                          if (!_otpStage) {
                            _phoneMessage = null;
                          }
                        });
                      },
                      onCountryChanged: (country) {
                        setState(() {
                          _selectedDialCode =
                              _normalizeDialCode('+${country.dialCode}');
                          _currentCountryCode = country.code;
                          _phoneHasError = false;
                          _phoneError = null;
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  _phoneMessage ??
                      (_otpCooldownSeconds > 0
                          ? 'Please try again in $_otpCooldownSeconds seconds before requesting another code.'
                          : 'We\'ll send a verification code via SMS.'),
                  style: TextStyle(
                    color: _phoneMessage != null ? _phoneMessageColor : Colors.black54,
                    height: 1.3,
                  ),
                ),
                if (_otpStage) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Enter Verification Codes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otpController,
                    enabled: !_isBusy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: _fieldTextStyle,
                    decoration: _profileFieldDecoration(
                      hintText: 'Enter the 6-digit code',
                      errorText: _otpError,
                    ).copyWith(counterText: ''),
                    onChanged: (_) => setState(() => _otpError = null),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_otpStage ? _canSave : _canSendOtp) ? onPrimary : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            primaryLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
