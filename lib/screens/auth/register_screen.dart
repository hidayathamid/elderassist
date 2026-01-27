import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/services/auth_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/auth_wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_chip.dart';
import 'package:emergencies_disability_assistance_app/services/geocoding_service.dart';
import 'login_screen.dart';

enum _RegisterFlowStep {
  role,
  account,
  services,
  location,
  caregiverIdentity,
  clientBudget,
  phone,
  otp,
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final TextEditingController _budgetCtrl = TextEditingController();
  final TextEditingController _idFrontCtrl = TextEditingController();
  final TextEditingController _idBackCtrl = TextEditingController();
  final TextEditingController _idSelfieCtrl = TextEditingController();
  final GlobalKey _addressFieldKey = GlobalKey();
  final FocusNode _addressFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  int _currentStep = 0;
  String? _selectedRole;

  final List<String> _selectedServices = [];

  String _fullPhoneNumber = '';

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  LatLng? _pickedLatLng;
  Marker? _marker;
  GoogleMapController? _mapCtrl;
  Completer<GoogleMapController> _mapControllerCompleter = Completer();
  MapType _mapType = MapType.normal;
  bool _locating = false;
  int _mapGeneration = 0;
  int _locationRequestSerial = 0;

  bool _isRegistering = false;
  bool _isSendingCode = false;
  bool _isCheckingEmail = false;
  bool _otpSent = false;
  String? _verificationId;
  bool _otpSessionExpired = false;
  bool _phoneHasError = false;
  String? _phoneMessage;
  Color _phoneMessageColor = Colors.black54;
  String? _roleError;
  String? _servicesError;
  String? _otpError;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;

  Uint8List? _idFrontBytes;
  String? _idFrontFileName;
  Uint8List? _idBackBytes;
  String? _idBackFileName;
  Uint8List? _idSelfieBytes;
  String? _idSelfieFileName;

  Future<void> _pickIdentityPhoto({
    required void Function(Uint8List bytes, String fileName) onPicked,
  }) async {
    final group = const XTypeGroup(
      label: 'image',
      extensions: ['jpg', 'jpeg', 'png'],
    );
    final XFile? picked = await openFile(
      acceptedTypeGroups: [group],
      confirmButtonText: 'Select',
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    onPicked(bytes, picked.name);
  }

  Future<void> _pickIdFront() async {
    await _pickIdentityPhoto(
      onPicked: (bytes, name) {
        setState(() {
          _idFrontBytes = bytes;
          _idFrontFileName = name;
          _idFrontCtrl.text = name;
        });
      },
    );
  }

  Future<void> _pickIdBack() async {
    await _pickIdentityPhoto(
      onPicked: (bytes, name) {
        setState(() {
          _idBackBytes = bytes;
          _idBackFileName = name;
          _idBackCtrl.text = name;
        });
      },
    );
  }

  Future<void> _pickIdSelfie() async {
    await _pickIdentityPhoto(
      onPicked: (bytes, name) {
        setState(() {
          _idSelfieBytes = bytes;
          _idSelfieFileName = name;
          _idSelfieCtrl.text = name;
        });
      },
    );
  }

  String _inferImageExtension(String? fileName) {
    final name = (fileName ?? '').trim().toLowerCase();
    if (name.endsWith('.png')) return 'png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'jpg';
    return 'jpg';
  }

  String _inferContentType(String extension) {
    return extension == 'png' ? 'image/png' : 'image/jpeg';
  }

  Future<Map<String, String>?> _uploadIdentityDocument({
    required String caregiverId,
    required Uint8List bytes,
    required String? originalFileName,
    required String documentName,
  }) async {
    final extension = _inferImageExtension(originalFileName);
    final contentType = _inferContentType(extension);
    final docRef = FirebaseFirestore.instance.collection('documents').doc();
    final storagePath = 'documents/$caregiverId/${docRef.id}.$extension';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final fileUrl = await ref.getDownloadURL();
    final fileNameValue = (originalFileName ?? '').trim().isNotEmpty
        ? originalFileName!.trim()
        : '${docRef.id}.$extension';
    await docRef.set({
      'caregiverId': caregiverId,
      'name': documentName,
      'fileName': fileNameValue,
      'status': false,
      'fileUrl': fileUrl,
      'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return {'id': docRef.id, 'name': documentName};
  }

  Future<void> _appendCaregiverDocuments(
    String caregiverId,
    List<Map<String, String>> docs,
  ) async {
    // No-op: caregiver applications are stored in `waitinglist` until verified.
    // Document metadata lives in the `documents` collection for admin review.
    return;
  }

  Future<void> _uploadCaregiverIdentityDocuments(String caregiverId) async {
    if (_idFrontBytes == null ||
        _idBackBytes == null ||
        _idSelfieBytes == null) {
      return;
    }
    final created = <Map<String, String>>[];
    try {
      final front = await _uploadIdentityDocument(
        caregiverId: caregiverId,
        bytes: _idFrontBytes!,
        originalFileName: _idFrontFileName,
        documentName: 'Identification card (Front)',
      );
      if (front != null) created.add(front);
      final back = await _uploadIdentityDocument(
        caregiverId: caregiverId,
        bytes: _idBackBytes!,
        originalFileName: _idBackFileName,
        documentName: 'Identification card (Back)',
      );
      if (back != null) created.add(back);
      final selfie = await _uploadIdentityDocument(
        caregiverId: caregiverId,
        bytes: _idSelfieBytes!,
        originalFileName: _idSelfieFileName,
        documentName: 'Selfie with identification card',
      );
      if (selfie != null) created.add(selfie);
    } catch (_) {
      // ignore upload failure (registration can still proceed)
    }
    await _appendCaregiverDocuments(caregiverId, created);
  }

  @override
  void initState() {
    super.initState();
    for (final ctrl in _trackedControllers) {
      ctrl.addListener(_onFieldChanged);
    }
    _addressFocus.addListener(() {
      if (_addressFocus.hasFocus) {
        _ensureAddressVisible();
      }
    });
    _otpCtrl.addListener(() {
      if (_otpError != null && mounted) {
        setState(() => _otpError = null);
      }
    });
  }

  List<TextEditingController> get _trackedControllers => [
    _firstNameCtrl,
    _lastNameCtrl,
    _emailCtrl,
    _passwordCtrl,
    _confirmPasswordCtrl,
    _phoneCtrl,
    _addressCtrl,
    _otpCtrl,
    _budgetCtrl,
    _idFrontCtrl,
    _idBackCtrl,
    _idSelfieCtrl,
  ];

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    for (final ctrl in _trackedControllers) {
      ctrl
        ..removeListener(_onFieldChanged)
        ..dispose();
    }
    _addressFocus.dispose();
    _scrollController.dispose();
    _mapCtrl?.dispose();
    _otpCooldownTimer?.cancel();
    super.dispose();
  }

  List<_RegisterFlowStep> get _flowSteps {
    final steps = <_RegisterFlowStep>[
      _RegisterFlowStep.role,
      _RegisterFlowStep.account,
      _RegisterFlowStep.services,
      _RegisterFlowStep.location,
    ];
    final role = (_selectedRole ?? '').trim().toLowerCase();
    if (role == 'caregiver') {
      steps.add(_RegisterFlowStep.caregiverIdentity);
    } else if (role.isNotEmpty) {
      steps.add(_RegisterFlowStep.clientBudget);
    }
    steps.addAll(const [_RegisterFlowStep.phone, _RegisterFlowStep.otp]);
    return steps;
  }

  int get _totalSteps => _flowSteps.length;

  _RegisterFlowStep get _currentFlowStep => _flowSteps[_currentStep];

  void _goToFlowStep(_RegisterFlowStep step) {
    final idx = _flowSteps.indexOf(step);
    if (idx == -1) return;
    setState(() => _currentStep = idx);
  }

  bool _isValidName(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return false;
    final re = RegExp(r"^[A-Za-z .'-]+$");
    return re.hasMatch(trimmed);
  }

  bool _isValidEmail(String value) {
    final re = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return re.hasMatch(value.trim());
  }

  String? _passwordStrength(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 16) {
      return 'Password must be at least 16 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(trimmed)) {
      return 'Password must include at least 1 uppercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(trimmed)) {
      return 'Password must include at least 1 number.';
    }
    // Any non-alphanumeric character counts as a symbol.
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(trimmed)) {
      return 'Password must include at least 1 symbol.';
    }
    return null;
  }

  bool get _isLastStep => _currentStep == _totalSteps - 1;

  double get _progress => (_currentStep + 1) / _totalSteps;

  Future<void> _autoDetectLocation() async {
    final expectedSerial = _locationRequestSerial;
    try {
      if (!mounted || _currentFlowStep != _RegisterFlowStep.location) return;
      setState(() => _locating = true);
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showSnack('Location services are disabled.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (!mounted ||
          _currentFlowStep != _RegisterFlowStep.location ||
          expectedSerial != _locationRequestSerial) {
        return;
      }
      final latLng = LatLng(pos.latitude, pos.longitude);
      await _placeMarker(latLng);
      if (!mounted ||
          _currentFlowStep != _RegisterFlowStep.location ||
          expectedSerial != _locationRequestSerial) {
        return;
      }
      final controller = await _mapControllerCompleter.future;
      try {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));
      } catch (_) {
        // ignore map controller errors (can happen when navigating between steps)
      }
    } catch (e) {
      _showSnack('Failed to detect location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _resetMapControllerState() {
    _locationRequestSerial++;
    _mapGeneration++;
    _mapCtrl = null;
    _mapControllerCompleter = Completer<GoogleMapController>();
    _locating = false;
  }

  void _handleRoleSelected(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final previous = (_selectedRole ?? '').trim().toLowerCase();
    setState(() {
      _selectedRole = normalized;
      _roleError = null;
      if (previous.isNotEmpty && previous != normalized) {
        _selectedServices.clear();
        _servicesError = null;
        _pickedLatLng = null;
        _marker = null;
        _addressCtrl.clear();
        _resetMapControllerState();
      }
    });
  }

  Future<void> _placeMarker(LatLng pos) async {
    setState(() {
      _pickedLatLng = pos;
      _marker = Marker(
        markerId: const MarkerId('picked'),
        position: pos,
        draggable: true,
        onDragEnd: (newPos) => _onMarkerDragged(newPos),
      );
    });
    await _reverseGeocode(pos.latitude, pos.longitude);
  }

  Future<void> _onMarkerDragged(LatLng pos) async {
    setState(() {
      _pickedLatLng = pos;
      _marker =
          _marker?.copyWith(positionParam: pos) ??
          Marker(
            markerId: const MarkerId('picked'),
            position: pos,
            draggable: true,
            onDragEnd: (p) => _onMarkerDragged(p),
          );
    });
    await _reverseGeocode(pos.latitude, pos.longitude);
  }

  String _formatPlacemark(Placemark p) {
    return [
      if (p.name != null && p.name!.isNotEmpty) p.name,
      if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality,
      if (p.locality != null && p.locality!.isNotEmpty) p.locality,
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
        p.administrativeArea,
      if (p.postalCode != null && p.postalCode!.isNotEmpty) p.postalCode,
      if (p.country != null && p.country!.isNotEmpty) p.country,
    ].join(', ');
  }

  void _ensureAddressVisible() {
    if (!mounted) return;
    final context = _addressFieldKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final parts = _formatPlacemark(placemarks.first);
        _addressCtrl.text = parts;
      }
    } catch (_) {
      // ignore reverse geocode errors
    }
  }

  void _handleBack() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    final leavingLocation = _currentFlowStep == _RegisterFlowStep.location;
    setState(() => _currentStep--);
    if (leavingLocation) {
      _resetMapControllerState();
    }
  }

  Future<void> _handleContinue() async {
    FocusScope.of(context).unfocus();

    if (_currentFlowStep == _RegisterFlowStep.otp && _otpSessionExpired) {
      await _sendOtp();
      return;
    }

    if (!_validateCurrentStep()) return;

    if (_currentFlowStep == _RegisterFlowStep.account) {
      final available = await _ensureEmailAvailable();
      if (!available) return;
    }

    if (_currentFlowStep == _RegisterFlowStep.phone) {
      final phoneOk = await _ensurePhoneAvailable();
      if (!phoneOk) return;
      await _sendOtp();
      return;
    }

    if (_isLastStep) {
      await _register();
      return;
    }

    setState(() => _currentStep++);
    if (_currentFlowStep == _RegisterFlowStep.location) {
      _resetMapControllerState();
      final serial = _locationRequestSerial;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted ||
          _currentFlowStep != _RegisterFlowStep.location ||
          serial != _locationRequestSerial) {
        return;
      }
      _autoDetectLocation();
    }
  }

  bool _validateCurrentStep() {
    setState(() {
      _roleError = null;
      _servicesError = null;
      _otpError = null;
    });

    switch (_currentFlowStep) {
      case _RegisterFlowStep.role:
        if (_selectedRole == null) {
          setState(() => _roleError = 'Please choose a role to continue.');
          return false;
        }
        return true;
      case _RegisterFlowStep.account:
        return _formKey.currentState?.validate() ?? false;
      case _RegisterFlowStep.services:
        if (_selectedServices.isEmpty) {
          setState(
            () => _servicesError = 'Select at least one service preference.',
          );
          return false;
        }
        return true;
      case _RegisterFlowStep.location:
        final valid = _formKey.currentState?.validate() ?? false;
        if (!valid) return false;
        if (_pickedLatLng == null) {
          _showSnack('Please confirm your map location.');
          return false;
        }
        return true;
      case _RegisterFlowStep.caregiverIdentity:
        if (_idFrontBytes == null ||
            _idBackBytes == null ||
            _idSelfieBytes == null) {
          _showSnack('Please upload all identification photos.');
          return false;
        }
        return true;
      case _RegisterFlowStep.clientBudget:
        final value = _budgetCtrl.text.trim();
        final parsed = double.tryParse(value);
        if (parsed == null || parsed <= 0) {
          _showSnack('Please enter a valid budget amount.');
          return false;
        }
        return true;
      case _RegisterFlowStep.phone:
        if (_fullPhoneNumber.trim().isEmpty) {
          setState(() {
            _phoneHasError = true;
            _phoneMessage = 'Please enter your phone number.';
            _phoneMessageColor = Colors.red;
          });
          return false;
        }
        return true;
      case _RegisterFlowStep.otp:
        final hasVerification = _otpSent || _verificationId != null;
        if (!hasVerification) {
          setState(() => _otpError = 'Request a verification code first.');
          return false;
        }
        if (!_otpSessionExpired && _otpCtrl.text.trim().length != 6) {
          setState(() => _otpError = 'Enter the 6-digit code.');
          return false;
        }
        return _formKey.currentState?.validate() ?? true;
    }
  }

  bool _isCurrentStepReady() {
    switch (_currentFlowStep) {
      case _RegisterFlowStep.role:
        return _selectedRole != null;
      case _RegisterFlowStep.account:
        return _firstNameCtrl.text.trim().isNotEmpty &&
            _lastNameCtrl.text.trim().isNotEmpty &&
            _emailCtrl.text.trim().isNotEmpty &&
            _passwordCtrl.text.isNotEmpty &&
            _confirmPasswordCtrl.text.isNotEmpty;
      case _RegisterFlowStep.services:
        return _selectedServices.isNotEmpty;
      case _RegisterFlowStep.location:
        return _pickedLatLng != null && _addressCtrl.text.trim().isNotEmpty;
      case _RegisterFlowStep.caregiverIdentity:
        return _idFrontBytes != null &&
            _idBackBytes != null &&
            _idSelfieBytes != null;
      case _RegisterFlowStep.clientBudget:
        return double.tryParse(_budgetCtrl.text.trim()) != null &&
            (double.tryParse(_budgetCtrl.text.trim()) ?? 0) > 0;
      case _RegisterFlowStep.phone:
        return _fullPhoneNumber.trim().isNotEmpty;
      case _RegisterFlowStep.otp:
        if (_otpSessionExpired) return true;
        final hasVerification = _otpSent || _verificationId != null;
        return hasVerification && _otpCtrl.text.trim().length == 6;
    }
  }

  Future<void> _sendOtp() async {
    if (_otpCooldownSeconds > 0) {
      _showSnack(
        'Please try again in $_otpCooldownSeconds seconds before requesting another code.',
      );
      return;
    }
    setState(() {
      _isSendingCode = true;
      _otpSent = false;
      _otpSessionExpired = false;
      _verificationId = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _fullPhoneNumber,
        verificationCompleted: (credential) {
          debugPrint('verifyPhoneNumber: verificationCompleted');
        },
        verificationFailed: (e) {
          debugPrint(
            'verifyPhoneNumber: verificationFailed code=${e.code} message=${e.message}',
          );
          final msg = (e.message ?? '').contains('BILLING_NOT_ENABLED')
              ? 'We could not send the code. Please try again.'
              : 'We could not send the verification code. Please try again.';
          setState(() {
            _phoneHasError = true;
            _phoneMessage = '$msg (${e.code})';
            _phoneMessageColor = Colors.red;
            _otpSent = false;
            _verificationId = null;
          });
          final errMsg = e.message ?? '';
          if (errMsg.toLowerCase().contains('blocked all requests')) {
            _startOtpCooldown();
            _showDialogMessage(
              title: 'Too many attempts',
              message:
                  'We blocked requests from this device because of unusual activity. Please try again later.',
            );
          }
        },
        codeSent: (verificationId, _) {
          debugPrint('verifyPhoneNumber: codeSent id=$verificationId');
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _otpCtrl.clear();
            _otpError = null;
            _phoneHasError = false;
            _phoneMessage = 'Verification code sent to $_fullPhoneNumber.';
            _phoneMessageColor = Colors.green;
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _phoneMessage = null;
                _phoneHasError = false;
                _phoneMessageColor = Colors.black54;
              });
              _goToFlowStep(_RegisterFlowStep.otp);
            }
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (error, stack) {
      debugPrint('sendOtp: exception $error');
      debugPrint('$stack');
      setState(() {
        _phoneHasError = true;
        _phoneMessage = 'Failed to send code. Please try again.';
        _phoneMessageColor = Colors.red;
      });
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  void _startOtpCooldown([int seconds = 60]) {
    _otpCooldownTimer?.cancel();
    setState(() {
      _otpCooldownSeconds = seconds;
      _phoneMessage =
          'Please wait $_otpCooldownSeconds seconds before requesting a new code.';
      _phoneMessageColor = Colors.orange;
    });
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpCooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _otpCooldownSeconds = 0;
          _phoneMessage = null;
          _phoneHasError = false;
          _phoneMessageColor = Colors.black54;
        });
        return;
      }
      setState(() => _otpCooldownSeconds--);
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDialogMessage({
    required String title,
    required String message,
    String buttonText = 'Continue',
    FutureOr<void> Function()? onContinue,
  }) async {
    if (!mounted) return;
    const Color primaryColor = Color(0xFFF4B63D);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: 180,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                final result = onContinue?.call();
                if (result is Future) {
                  unawaited(result);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureEmailAvailable() async {
    final email = _emailCtrl.text.trim();
    setState(() => _isCheckingEmail = true);
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        if (!mounted) return false;
        await _showDialogMessage(
          title: 'Email already registered',
          message:
              'This email has already been registered. Please proceed to the login page.',
          buttonText: 'Continue',
          onContinue: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LoginScreen.prefilled(email)),
            );
          },
        );
        return false;
      }
      return true;
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Unable to validate email');
      return false;
    } catch (e) {
      _showSnack('Unable to validate email: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isCheckingEmail = false);
    }
  }

  Future<bool> _ensurePhoneAvailable() async {
    final phone = _fullPhoneNumber.trim();
    if (phone.isEmpty) return false;
    setState(() {
      _phoneHasError = false;
      _phoneMessage = null;
    });
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        setState(() {
          _phoneHasError = true;
          _phoneMessage =
              'This number is already registered in the system. Please use another number.';
          _phoneMessageColor = Colors.red;
          _phoneCtrl.clear();
          _fullPhoneNumber = '';
        });
        return false;
      }
      setState(() {
        _phoneHasError = false;
        _phoneMessage = null;
      });
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

  Future<void> _register() async {
    if (_isRegistering) return;
    setState(() => _isRegistering = true);

    try {
      final nameParts = [
        _firstNameCtrl.text.trim(),
        _lastNameCtrl.text.trim(),
      ].where((part) => part.isNotEmpty).toList();
      final fullName = nameParts.join(' ');
      final email = _emailCtrl.text.trim();
      final pwd = _passwordCtrl.text;

      if (_selectedRole == null) {
        _showSnack('Select a role first.');
        _goToFlowStep(_RegisterFlowStep.role);
        return;
      }

      final pwdMsg = _passwordStrength(pwd);
      if (pwdMsg != null) {
        _showSnack(pwdMsg);
        _goToFlowStep(_RegisterFlowStep.account);
        return;
      }

      if (_verificationId == null) {
        _showSnack('Please request and enter the verification code first.');
        setState(() => _otpError = 'Enter the code sent to your phone.');
        _goToFlowStep(_RegisterFlowStep.otp);
        return;
      }

      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: _otpCtrl.text.trim(),
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
        await FirebaseAuth.instance.signOut();
      } on FirebaseAuthException catch (e) {
        final message = (e.message ?? '').toLowerCase();
        final code = e.code.toLowerCase();
        final isExpired =
            code.contains('session-expired') ||
            message.contains('code has expired') ||
            message.contains('session expired') ||
            message.contains('expired');
        setState(() {
          _otpSessionExpired = isExpired;
          _otpError = isExpired
              ? 'The verification code has expired. Tap "Resend code" to get a new one.'
              : (e.message ?? 'Invalid code. Please try again.');
          _otpSent = true;
        });
        return;
      }

      final trimmedAddress = _addressCtrl.text.trim();
      final coords = await _resolveAddressCoordinates(trimmedAddress);
      final res = await _authService.registerUser(
        name: fullName,
        email: email,
        password: pwd,
        // Caregiver applicants are registered as normal users first. Their
        // caregiver application stays in `waitinglist` until verified.
        role: 'user',
        phone: _fullPhoneNumber,
        defaultAddress: trimmedAddress.isNotEmpty ? trimmedAddress : null,
        lat: coords?.latitude,
        lng: coords?.longitude,
      );

      if (res == null) {
        _showSnack('Failed to register');
        return;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final waitingRef =
          FirebaseFirestore.instance.collection('waitinglist').doc(uid);
      final extras = <String, dynamic>{
        'servicePreferences': _selectedServices,
        'phoneVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'caregiver') {
        await userRef.update(extras);
        await waitingRef.set(
          {
            'userId': uid,
            'name': fullName,
            'email': email,
            'phone': _fullPhoneNumber,
            'defaultAddress': trimmedAddress.isNotEmpty ? trimmedAddress : null,
            if (coords?.latitude != null) 'lat': coords!.latitude,
            if (coords?.longitude != null) 'lng': coords!.longitude,
            'servicePreferences': _selectedServices,
            'verified': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        await _uploadCaregiverIdentityDocuments(uid);
      } else {
        final budget = double.tryParse(_budgetCtrl.text.trim());
        if (budget != null && budget > 0) {
          extras['budget'] = budget;
        }
        await userRef.update(extras);
      }

      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      await _showDialogMessage(
        title: 'Registration Successful',
        message: 'Your ElderAssist account is ready.',
        buttonText: 'Login',
        onContinue: () async {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => LoginScreen.prefilled(email)),
            (route) => false,
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      await _showDialogMessage(
        title: 'Authentication error',
        message: e.message ?? 'Authentication error',
      );
    } catch (e) {
      await _showDialogMessage(
        title: 'Registration failed',
        message:
            'Fail to sign up your account to the system. Please try again.',
        buttonText: 'Continue',
        onContinue: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (route) => false,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  Future<LatLng?> _resolveAddressCoordinates(String address) async {
    if (_pickedLatLng != null) return _pickedLatLng;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    return await geocodeAddress(trimmed);
  }

  Widget _buildStepContent() {
    switch (_currentFlowStep) {
      case _RegisterFlowStep.role:
        return _buildRoleStep();
      case _RegisterFlowStep.account:
        return _buildAccountStep();
      case _RegisterFlowStep.services:
        return _buildServiceStep();
      case _RegisterFlowStep.location:
        return _buildLocationStep();
      case _RegisterFlowStep.caregiverIdentity:
        return _buildCaregiverIdentityStep();
      case _RegisterFlowStep.clientBudget:
        return _buildClientBudgetStep();
      case _RegisterFlowStep.phone:
        return _buildPhoneStep();
      case _RegisterFlowStep.otp:
        return _buildOtpStep();
    }
  }

  Widget _buildRoleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _roleOption(
              title: 'Client',
              subtitle: 'Request care and assistance',
              icon: Icons.favorite_outline,
              isSelected: _selectedRole == 'user',
              onTap: () => _handleRoleSelected('user'),
            ),
            _roleOption(
              title: 'Caregiver',
              subtitle: 'Provide professional support',
              icon: Icons.medical_services_outlined,
              isSelected: _selectedRole == 'caregiver',
              onTap: () => _handleRoleSelected('caregiver'),
            ),
          ],
        ),
        if (_roleError != null) ...[
          const SizedBox(height: 12),
          Text(
            _roleError!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _roleOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 180,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF00A8A7) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? const Color(0xFFE5F7F6) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.black87),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountStep() {
    final passwordValue = _passwordCtrl.text;
    final passwordHelp = passwordValue.isEmpty
        ? null
        : _passwordStrength(passwordValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _labeledField(
                label: 'First name',
                controller: _firstNameCtrl,
                hintText: 'First Name',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter first name';
                  }
                  if (!_isValidName(value)) {
                    return 'Invalid name';
                  }
                  return null;
                },
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _labeledField(
                label: 'Last name',
                controller: _lastNameCtrl,
                hintText: 'Last Name',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter last name';
                  }
                  if (!_isValidName(value)) {
                    return 'Invalid name';
                  }
                  return null;
                },
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Your email',
          controller: _emailCtrl,
          hintText: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter your email';
            }
            if (!_isValidEmail(value.trim())) {
              return 'Invalid email.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Password',
          controller: _passwordCtrl,
          hintText: 'Password',
          obscureText: !_showPassword,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          suffix: IconButton(
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(
              _showPassword ? Icons.visibility_off_outlined : Icons.visibility,
              color: Colors.grey[600],
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Enter password';
            }
            final msg = _passwordStrength(value);
            if (msg != null) return msg;
            return null;
          },
        ),
        const SizedBox(height: 4),
        if (passwordValue.isEmpty)
          const Text(
            'Atleast contains 1 uppercase/number/symbol.',
            style: TextStyle(color: Colors.black45),
          )
        else if (passwordHelp == null)
          const Text(
            'Password looks good.',
            style: TextStyle(color: Colors.black45),
          ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Confirm password',
          controller: _confirmPasswordCtrl,
          hintText: 'Confirm Password',
          obscureText: !_showConfirmPassword,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _showConfirmPassword = !_showConfirmPassword),
            icon: Icon(
              _showConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility,
              color: Colors.grey[600],
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Confirm your password';
            }
            if (value != _passwordCtrl.text) {
              return 'Passwords do not match. Please try again.';
            }
            return null;
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'Passwords must match.',
          style: TextStyle(color: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildServiceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const SizedBox(height: 4),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('services')
              .orderBy('name')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Unable to load services. Please try again.',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final names =
                snapshot.data!.docs
                    .map((d) => ((d.data()['name'] as String?) ?? '').trim())
                    .where((n) => n.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();
            if (names.isEmpty) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No services available yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }
            return Wrap(
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: names.map((service) {
                final isSelected = _selectedServices.contains(service);
                return ServiceChip(
                  label: service,
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedServices.remove(service);
                      } else {
                        _selectedServices.add(service);
                      }
                    });
                  },
                );
              }).toList(),
            );
          },
        ),
        if (_servicesError != null) ...[
          const SizedBox(height: 12),
          Text(
            _servicesError!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ],
      ],
    );
  }

  InputDecoration _documentFieldDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.black38),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.black87, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.red, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.red, width: 1.3),
      ),
    );
  }

  Widget _documentPickerField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: true,
          onTap: onPick,
          decoration: _documentFieldDecoration(hintText: 'Select a file')
              .copyWith(
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    icon: const Icon(Icons.upload_file, size: 18),
                    color: Colors.black87,
                    onPressed: onPick,
                  ),
                ),
              ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Select a file.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCaregiverIdentityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Text(
          'Upload your identification photos.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        _documentPickerField(
          label: 'Front identification card',
          controller: _idFrontCtrl,
          onPick: _pickIdFront,
        ),
        const SizedBox(height: 12),
        _documentPickerField(
          label: 'Back identification card',
          controller: _idBackCtrl,
          onPick: _pickIdBack,
        ),
        const SizedBox(height: 12),
        _documentPickerField(
          label: 'Selfie holding identification card',
          controller: _idSelfieCtrl,
          onPick: _pickIdSelfie,
        ),
        const SizedBox(height: 6),
        const Text(
          'Clear photos help us verify your caregiver account faster.',
          style: TextStyle(color: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildClientBudgetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Text(
          'Set your budget so we can match the right caregivers.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        _labeledField(
          label: 'Budget (RM)',
          controller: _budgetCtrl,
          hintText: 'e.g. 50',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          validator: (value) {
            final raw = (value ?? '').trim();
            final parsed = double.tryParse(raw);
            if (parsed == null || parsed <= 0) {
              return 'Enter a valid budget amount.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildLocationStep() {
    final double mapHeight = (MediaQuery.of(context).size.height * 0.24)
        .clamp(150.0, 200.0)
        .toDouble();
    final LatLng initialTarget =
        _pickedLatLng ?? const LatLng(3.1390, 101.6869);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: mapHeight,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: GoogleMap(
                  key: ValueKey<int>(_mapGeneration),
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: _pickedLatLng == null ? 12 : 15,
                  ),
                  mapType: _mapType,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onMapCreated: (controller) {
                    _mapCtrl = controller;
                    _mapControllerCompleter = Completer<GoogleMapController>();
                    _mapControllerCompleter.complete(controller);
                  },
                  markers: _marker != null ? {_marker!} : <Marker>{},
                  onTap: (pos) => _placeMarker(pos),
                ),
              ),
              if (_locating)
                const Positioned.fill(
                  child: Center(child: CircularProgressIndicator()),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  children: [
                    _mapControlButton(
                      icon: Icons.layers_outlined,
                      tooltip: 'Toggle map view',
                      onTap: () {
                        setState(() {
                          _mapType = _mapType == MapType.normal
                              ? MapType.satellite
                              : MapType.normal;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _mapControlButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Current location',
                      onTap: _autoDetectLocation,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Address',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            TextFormField(
              key: _addressFieldKey,
              controller: _addressCtrl,
              focusNode: _addressFocus,
              maxLines: 2,
              readOnly: true,
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: InputDecoration(
                hintText: 'Enter your full address',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: Colors.black87, width: 1.2),
                ),
                errorBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: Colors.red, width: 1.2),
                ),
                focusedErrorBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: Colors.red, width: 1.3),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Confirm your address';
                }
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Drag or tap on the map to fine-tune your address.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 20, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            colorScheme: const ColorScheme.light(primary: Colors.black),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Colors.black87, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Colors.black87, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
            ),
          ),
          child: IntlPhoneField(
            controller: _phoneCtrl,
            initialCountryCode: 'MY',
            disableLengthCheck: true,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
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
              searchFieldPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              searchFieldInputDecoration: InputDecoration(
                hintText: 'Search country',
                hintStyle: const TextStyle(color: Colors.black54),
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  borderSide: BorderSide(color: Colors.black87, width: 1.2),
                ),
              ),
            ),
            decoration: InputDecoration(
              hintText: '123 4567 890',
              hintStyle: const TextStyle(color: Colors.black38),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: _phoneHasError ? Colors.red : Colors.grey[300]!,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: _phoneHasError ? Colors.red : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(
                  color: _phoneHasError ? Colors.red : Colors.black87,
                  width: 1.2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            onChanged: (phone) {
              final rawNumber = phone.number.trim();
              final dialCode = phone.countryCode.trim(); // e.g. +60
              var national = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
              if (phone.countryISOCode.toUpperCase() == 'MY') {
                // Avoid +60012... when users enter Malaysian numbers with a leading 0.
                national = national.replaceFirst(RegExp(r'^0+'), '');
              }
              final normalized = national.isEmpty
                  ? ''
                  : '${dialCode.startsWith('+') ? dialCode : '+$dialCode'}$national';

              setState(() {
                _fullPhoneNumber = normalized;
                _phoneHasError = false;
                _phoneMessage = null;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _phoneMessage ?? 'We\'ll send a verification code via SMS.',
          style: TextStyle(
            color: _phoneMessage != null ? _phoneMessageColor : Colors.black54,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Code sent to $_fullPhoneNumber',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Verification code',
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          validator: (value) {
            if (_currentFlowStep != _RegisterFlowStep.otp) return null;
            if (value == null || value.trim().length != 6) {
              return 'Enter the 6-digit code.';
            }
            return null;
          },
        ),
        if (_otpError != null)
          Text(
            _otpError!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
      ],
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? hintText,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.black38),
            filled: true,
            fillColor: Colors.white,
            counterText: maxLength != null ? '' : null,
            suffixIcon: suffix,
            contentPadding:
                contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.black87, width: 1.2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.red, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.red, width: 1.3),
            ),
          ),
        ),
      ],
    );
  }

  String get _actionLabel {
    if (_isSendingCode) return 'Sending code...';
    if (_currentFlowStep == _RegisterFlowStep.phone) {
      return 'Send verification code';
    }
    if (_currentFlowStep == _RegisterFlowStep.otp && _otpSessionExpired) {
      return 'Resend code';
    }
    if (_isLastStep) return 'Create account';
    return 'Continue';
  }

  @override
  Widget build(BuildContext context) {
    final isExpiredResend =
        _currentFlowStep == _RegisterFlowStep.otp && _otpSessionExpired;
    final isOtpCooldownLocked =
        (_currentFlowStep == _RegisterFlowStep.phone || isExpiredResend) &&
        _otpCooldownSeconds > 0;
    final canSubmit =
        (isExpiredResend
            ? _fullPhoneNumber.trim().isNotEmpty
            : _isCurrentStepReady()) &&
        !_isRegistering &&
        !_isSendingCode &&
        !_isCheckingEmail &&
        !isOtpCooldownLocked;
    const Color primaryColor = Color(0xFFF4B63D);
    const Color disabledColor = Color(0xFFE5E5E5);
    final bool showLoader =
        _isRegistering || _isSendingCode || _isCheckingEmail;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: _handleBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minHeight: 36,
                          minWidth: 36,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Step ${_currentStep + 1} of $_totalSteps',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          color: const Color(0xFF00A8A7),
                          backgroundColor: Colors.grey[300],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _stepTitle,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stepSubtitle,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scrollPhysics =
                          (_currentFlowStep == _RegisterFlowStep.location ||
                              _currentFlowStep == _RegisterFlowStep.phone ||
                              _currentFlowStep == _RegisterFlowStep.otp)
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics();
                      final bottomInset = MediaQuery.of(
                        context,
                      ).viewInsets.bottom;
                      return SingleChildScrollView(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: scrollPhysics,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          8,
                          24,
                          8 + bottomInset,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Form(
                            key: _formKey,
                            child: _buildStepContent(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canSubmit ? _handleContinue : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmit
                                ? primaryColor
                                : disabledColor,
                            foregroundColor: canSubmit
                                ? Colors.black
                                : Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: showLoader
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: canSubmit
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                )
                              : Text(_actionLabel),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(color: Colors.black87),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Log in',
                              style: TextStyle(
                                color: Color(0xFF00A8A7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _stepTitle {
    switch (_currentFlowStep) {
      case _RegisterFlowStep.role:
        return 'Choose your role';
      case _RegisterFlowStep.account:
        return 'Let\'s create your account';
      case _RegisterFlowStep.services:
        return 'Service preferences';
      case _RegisterFlowStep.location:
        return 'Confirm your location';
      case _RegisterFlowStep.caregiverIdentity:
        return 'Verify your identity';
      case _RegisterFlowStep.clientBudget:
        return 'Set your budget';
      case _RegisterFlowStep.phone:
        return 'Verify your phone number';
      case _RegisterFlowStep.otp:
        return 'Enter the verification code';
    }
  }

  String get _stepSubtitle {
    switch (_currentFlowStep) {
      case _RegisterFlowStep.role:
        return 'Tell us whether you are requesting care or providing it.';
      case _RegisterFlowStep.account:
        return 'Share your details so we can secure your account.';
      case _RegisterFlowStep.services:
        return 'Select the services that best describe your needs.';
      case _RegisterFlowStep.location:
        return 'We use your location to match nearby caregivers.';
      case _RegisterFlowStep.caregiverIdentity:
        return 'Upload your identification photos for verification.';
      case _RegisterFlowStep.clientBudget:
        return 'Set a budget range for your bookings.';
      case _RegisterFlowStep.phone:
        return 'We\'ll contact you for ElderAssist services.';
      case _RegisterFlowStep.otp:
        return 'Check your SMS inbox for the 6-digit code.';
    }
  }
}
