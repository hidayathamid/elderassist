import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/main.dart';
import 'package:emergencies_disability_assistance_app/screens/auth/login_screen.dart';
import 'package:emergencies_disability_assistance_app/services/post_login_action.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _dialogBackground = Color(0xFFF7F8FA);
const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);

enum _EmailFlowState { idle, sending, awaitingVerification, completing }

class ProfileEmailEditScreen extends StatefulWidget {
  const ProfileEmailEditScreen({
    super.key,
    required this.initialEmail,
    required this.isCaregiver,
  });

  final String initialEmail;
  final bool isCaregiver;

  @override
  State<ProfileEmailEditScreen> createState() => _ProfileEmailEditScreenState();
}

class _ProfileEmailEditScreenState extends State<ProfileEmailEditScreen>
    with WidgetsBindingObserver {
  final TextEditingController _currentEmailController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  String? _error;
  _EmailFlowState _state = _EmailFlowState.idle;
  String? _pendingNewEmail;
  bool _completed = false;
  bool _loadingPending = false;

  String get _collectionName => widget.isCaregiver ? 'caregivers' : 'users';

  DocumentReference<Map<String, dynamic>>? _userDocRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return null;
    return FirebaseFirestore.instance.collection(_collectionName).doc(uid);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentEmailController.text = widget.initialEmail;
    _newEmailController.addListener(_validate);
    _validate();
    // ignore: discarded_futures
    _syncPendingAndMaybeComplete(showDialogs: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _currentEmailController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  void _validate() {
    final email = _newEmailController.text.trim();
    final emailLower = email.toLowerCase();
    final error = email.isEmpty
        ? 'Email is required'
        : (!emailLower.endsWith('@gmail.com') ||
                  emailLower.length <= '@gmail.com'.length
              ? 'Email must end with @gmail.com'
              : null);
    if (error != _error) setState(() => _error = error);
  }

  Future<void> _loadPendingFromFirestore() async {
    if (_loadingPending) return;
    final ref = _userDocRef();
    if (ref == null) return;

    _loadingPending = true;
    try {
      final snap = await ref.get();
      final data = snap.data();
      final pending = (data?['pendingEmailChange'] ?? '').toString().trim();
      if (pending.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _pendingNewEmail = pending;
        _newEmailController.text = pending;
        _error = null;
        if (!_completed && _state != _EmailFlowState.completing) {
          _state = _EmailFlowState.awaitingVerification;
        }
      });
    } catch (_) {
      // ignore: empty_catches
    } finally {
      _loadingPending = false;
    }
  }

  Future<void> _savePendingToFirestore(String email) async {
    final ref = _userDocRef();
    if (ref == null) return;
    try {
      await ref.set({
        'pendingEmailChange': email,
        'pendingEmailChangeAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore: empty_catches
    }
  }

  Future<void> _clearPendingFromFirestore() async {
    final ref = _userDocRef();
    if (ref == null) return;
    try {
      await ref.set({
        'pendingEmailChange': FieldValue.delete(),
        'pendingEmailChangeAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore: empty_catches
    }
  }

  Future<void> _syncPendingAndMaybeComplete({required bool showDialogs}) async {
    if ((_pendingNewEmail ?? '').trim().isEmpty) {
      await _loadPendingFromFirestore();
    }
    await _tryCompleteAfterVerification(
      showDialogs: showDialogs,
      showSuccessDialogOnSuccess: true,
    );
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
    required VoidCallback onOk,
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
              onPressed: () {
                Navigator.of(context).pop();
                onOk();
              },
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

  Future<bool> _showSessionExpiredDialog({
    required String suggestedEmail,
  }) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: _dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Session expired',
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: Text(
          'Your session has expired, so we can’t complete the email change yet.\n\nPlease sign in again to finish updating your profile email.',
          textAlign: TextAlign.center,
          style: _dialogContentStyle,
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
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
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
                  child: const Text('Sign out & continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == true) {
      await _signOutAndGoToLogin(prefilledEmail: suggestedEmail);
      return true;
    }
    return false;
  }

  Future<void> _signOutAndGoToLogin({required String prefilledEmail}) async {
    final trimmed = prefilledEmail.trim();
    PostLoginAction.set(
      PostLoginAction(type: PostLoginActionType.openEmailEdit),
    );
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen.prefilled(trimmed)),
      (_) => false,
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!mounted) return false;
    final hasPending =
        (_newEmailController.text.trim().isNotEmpty ||
            (_pendingNewEmail ?? '').trim().isNotEmpty) &&
        !_completed &&
        _state != _EmailFlowState.completing;
    if (!hasPending) return true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
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
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
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
    final ok = await _confirmDiscard();
    if (!ok || !mounted) return;
    // Ensure "discard" really discards for next open too.
    await _clearPendingFromFirestore();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<String?> _promptForPassword() async {
    if (!mounted) return null;
    final controller = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Re-authentication required',
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'For security, please re-enter your password to continue.',
              textAlign: TextAlign.center,
              style: _dialogContentStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Password',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: _profileDarkText, width: 1.1),
                ),
              ),
            ),
          ],
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
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () {
                    result = controller.text;
                    Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = (result ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> _reauthenticateIfPossible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (!providers.contains('password')) {
      await _showInfoDialog(
        title: 'Re-login required',
        message:
            'This account needs a recent login to change email.\n\nPlease sign out and sign in again, then retry.',
        onOk: () {},
      );
      return false;
    }

    final password = await _promptForPassword();
    if (password == null) return false;

    try {
      final email = (user.email ?? widget.initialEmail).trim();
      if (email.isEmpty) return false;
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      final msg = (e.message ?? '').trim();
      await _showInfoDialog(
        title: 'Unable to re-authenticate',
        message: msg.isNotEmpty ? msg : e.code,
        onOk: () {},
      );
      return false;
    } catch (e) {
      await _showInfoDialog(
        title: 'Unable to re-authenticate',
        message: '$e',
        onOk: () {},
      );
      return false;
    }
  }

  Future<void> _sendVerification({bool didReauthRetry = false}) async {
    if (_state == _EmailFlowState.sending ||
        _state == _EmailFlowState.completing) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    if (uid.trim().isEmpty) return;

    final newEmail = _newEmailController.text.trim();
    if (_error != null || newEmail.isEmpty) return;

    setState(() {
      _state = _EmailFlowState.sending;
      _pendingNewEmail = newEmail;
    });
    try {
      await user!.verifyBeforeUpdateEmail(newEmail);
      if (!mounted) return;
      setState(() => _state = _EmailFlowState.awaitingVerification);
      // ignore: discarded_futures
      _savePendingToFirestore(newEmail);
      await _showInfoDialog(
        title: 'Verification sent',
        message:
            'We sent a verification link to:\n\n$newEmail\n\nPlease verify the email, then return to the app.',
        onOk: () {},
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login' && !didReauthRetry) {
        final ok = await _reauthenticateIfPossible();
        if (!mounted) return;
        if (ok) {
          setState(() => _state = _EmailFlowState.idle);
          return await _sendVerification(didReauthRetry: true);
        }
      }
      final msg = (e.message ?? '').trim();
      setState(() {
        _state = _EmailFlowState.idle;
        _error = msg.isNotEmpty ? msg : e.code;
      });
    } finally {
      if (mounted && _state == _EmailFlowState.sending) {
        setState(() => _state = _EmailFlowState.idle);
      }
    }
  }

  Future<void> _tryCompleteAfterVerification({
    bool showDialogs = true,
    bool showSuccessDialogOnSuccess = true,
  }) async {
    var pending = (_pendingNewEmail ?? '').trim();
    if (pending.isEmpty) {
      await _loadPendingFromFirestore();
      pending = (_pendingNewEmail ?? '').trim();
    }
    if (pending.isEmpty) {
      if (showDialogs) {
        await _showInfoDialog(
          title: 'Nothing to verify',
          message:
              'No pending email change found.\n\nPlease enter your new email and tap Verify again.',
          onOk: () {},
        );
      }
      return;
    }
    if (_state == _EmailFlowState.completing) return;
    if (_completed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _state = _EmailFlowState.completing);
    try {
      try {
        await user.getIdToken(true);
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        final code = e.code;
        final isTokenExpired =
            code == 'user-token-expired' || code == 'invalid-user-token';
        setState(() {
          _error = isTokenExpired
              ? 'Session expired. Please sign in again to complete the email change.'
              : ((e.message ?? '').trim().isNotEmpty
                    ? e.message!.trim()
                    : code);
        });
        if (showDialogs) {
          if (isTokenExpired) {
            await _showSessionExpiredDialog(suggestedEmail: pending);
          } else {
            await _showInfoDialog(
              title: 'Session expired',
              message: _error ?? code,
              onOk: () {},
            );
          }
        }
        return;
      }
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      final currentEmail = (refreshed?.email ?? '').trim();
      if (currentEmail.toLowerCase() != pending.toLowerCase()) {
        if (mounted) {
          setState(() {
            _error =
                "Not verified yet. Open the verification link in $pending, then come back and try again.";
          });
        }
        if (showDialogs) {
          await _showInfoDialog(
            title: 'Not verified yet',
            message:
                "We still can't confirm the email change.\n\nPlease open the verification link in $pending, then come back and try again.",
            onOk: () {},
          );
        }
        return;
      }

      final uid = refreshed?.uid ?? '';
      if (uid.trim().isEmpty) return;

      final ref = FirebaseFirestore.instance
          .collection(widget.isCaregiver ? 'caregivers' : 'users')
          .doc(uid);
      await ref.set({
        'email': pending,
        'pendingEmailChange': FieldValue.delete(),
        'pendingEmailChangeAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _completed = true;
        _error = null;
      });
      // ignore: discarded_futures
      _clearPendingFromFirestore();
      if (showSuccessDialogOnSuccess) {
        await _showInfoDialog(
          title: 'Successful',
          message: 'Email has been verified and updated successfully.',
          onOk: () => Navigator.of(context).pop(pending),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        final ok = await _reauthenticateIfPossible();
        if (!mounted) return;
        if (ok) {
          setState(() => _state = _EmailFlowState.idle);
          return _tryCompleteAfterVerification(
            showDialogs: showDialogs,
            showSuccessDialogOnSuccess: showSuccessDialogOnSuccess,
          );
        }
      }
      setState(() {
        _error = (e.message ?? '').trim().isNotEmpty
            ? e.message!.trim()
            : e.code;
      });
      if (showDialogs) {
        await _showInfoDialog(
          title: 'Unable to complete',
          message: _error ?? e.code,
          onOk: () {},
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      if (showDialogs) {
        await _showInfoDialog(
          title: 'Unable to complete',
          message: _error ?? '$e',
          onOk: () {},
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _state = _completed
              ? _EmailFlowState.idle
              : _EmailFlowState.awaitingVerification;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      _syncPendingAndMaybeComplete(showDialogs: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAwaiting = _state == _EmailFlowState.awaitingVerification;
    final enteredEmail = _newEmailController.text.trim();
    final pendingEmail = (_pendingNewEmail ?? '').trim();
    final canVerify =
        _state != _EmailFlowState.sending &&
        _state != _EmailFlowState.completing &&
        (isAwaiting
            ? pendingEmail.isNotEmpty
            : (_error == null && enteredEmail.isNotEmpty));
    final isSuccessful = _completed;
    final buttonLabel = isSuccessful
        ? 'Successful'
        : (isAwaiting ? 'I have verified' : 'Verify');
    final VoidCallback? buttonAction = (!isSuccessful && canVerify)
        ? (isAwaiting
              ? () => _tryCompleteAfterVerification()
              : _sendVerification)
        : null;

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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _profileDarkText,
          ),
          title: const Text(
            'Edit Email',
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
                  'Current Email',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _currentEmailController,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Current Email',
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: BorderSide(
                        color: _profileDarkText,
                        width: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'New Email',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _newEmailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled:
                      _state != _EmailFlowState.sending &&
                      _state != _EmailFlowState.completing &&
                      !isAwaiting &&
                      !_completed,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New Email',
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: BorderSide(
                        color: _profileDarkText,
                        width: 1.1,
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 6),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: buttonAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child:
                        _state == _EmailFlowState.sending ||
                            _state == _EmailFlowState.completing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            buttonLabel,
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
