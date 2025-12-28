import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/models/user_model.dart';
import 'package:emergencies_disability_assistance_app/screens/caregiver/caregiver_root_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/user_root_screen.dart';
import 'package:emergencies_disability_assistance_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:emergencies_disability_assistance_app/constants/service_options.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_chip.dart';
import 'touchdown_screen.dart';

import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _totalSteps = 6;

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
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();
  MapType _mapType = MapType.normal;
  bool _locating = false;

  bool _isRegistering = false;
  bool _isSendingCode = false;
  bool _isCheckingEmail = false;
  bool _otpSent = false;
  String? _verificationId;
  bool _phoneHasError = false;
  String? _phoneMessage;
  Color _phoneMessageColor = Colors.black54;
  String? _roleError;
  String? _servicesError;
  String? _otpError;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;

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
    if (value.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  bool get _isLastStep => _currentStep == _totalSteps - 1;

  double get _progress => (_currentStep + 1) / _totalSteps;

  Future<void> _autoDetectLocation() async {
    try {
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
      final latLng = LatLng(pos.latitude, pos.longitude);
      await _placeMarker(latLng);
      final controller = await _mapControllerCompleter.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));
    } catch (e) {
      _showSnack('Failed to detect location: $e');
    } finally {
      setState(() => _locating = false);
    }
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
    setState(() => _currentStep--);
  }

  Future<void> _handleContinue() async {
    FocusScope.of(context).unfocus();
    if (!_validateCurrentStep()) return;

    if (_currentStep == 1) {
      final available = await _ensureEmailAvailable();
      if (!available) return;
    }

    if (_currentStep == 4) {
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
    if (_currentStep == 3) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _autoDetectLocation();
    }
  }

  bool _validateCurrentStep() {
    setState(() {
      _roleError = null;
      _servicesError = null;
      _otpError = null;
    });

    switch (_currentStep) {
      case 0:
        if (_selectedRole == null) {
          setState(() => _roleError = 'Please choose a role to continue.');
          return false;
        }
        return true;
      case 1:
        return _formKey.currentState?.validate() ?? false;
      case 2:
        if (_selectedServices.isEmpty) {
          setState(
            () => _servicesError = 'Select at least one service preference.',
          );
          return false;
        }
        return true;
      case 3:
        final valid = _formKey.currentState?.validate() ?? false;
        if (!valid) return false;
        if (_pickedLatLng == null) {
          _showSnack('Please confirm your map location.');
          return false;
        }
        return true;
      case 4:
        if (_fullPhoneNumber.trim().isEmpty) {
          setState(() {
            _phoneHasError = true;
            _phoneMessage = 'Please enter your phone number.';
            _phoneMessageColor = Colors.red;
          });
          return false;
        }
        return true;
      case 5:
        final hasVerification = _otpSent || _verificationId != null;
        if (!hasVerification) {
          setState(() => _otpError = 'Request a verification code first.');
          return false;
        }
        if (_otpCtrl.text.trim().length != 6) {
          setState(() => _otpError = 'Enter the 6-digit code.');
          return false;
        }
        return _formKey.currentState?.validate() ?? true;
      default:
        return true;
    }
  }

  bool _isCurrentStepReady() {
    switch (_currentStep) {
      case 0:
        return _selectedRole != null;
      case 1:
        return _firstNameCtrl.text.trim().isNotEmpty &&
            _lastNameCtrl.text.trim().isNotEmpty &&
            _emailCtrl.text.trim().isNotEmpty &&
            _passwordCtrl.text.isNotEmpty &&
            _confirmPasswordCtrl.text.isNotEmpty;
      case 2:
        return _selectedServices.isNotEmpty;
      case 3:
        return _pickedLatLng != null && _addressCtrl.text.trim().isNotEmpty;
      case 4:
        return _fullPhoneNumber.trim().isNotEmpty;
      case 5:
        final hasVerification = _otpSent || _verificationId != null;
        return hasVerification && _otpCtrl.text.trim().length == 6;
      default:
        return false;
    }
  }

  Future<void> _sendOtp() async {
    if (_otpCooldownSeconds > 0) {
      _showSnack(
          'Please try again in $_otpCooldownSeconds seconds before requesting another code.');
      return;
    }
    setState(() {
      _isSendingCode = true;
      _otpSent = false;
      _verificationId = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _fullPhoneNumber,
        verificationCompleted: (credential) {
          debugPrint('verifyPhoneNumber: verificationCompleted');
        },
        verificationFailed: (e) {
          debugPrint('verifyPhoneNumber: verificationFailed ${e.message}');
          final msg = (e.message ?? '').contains('BILLING_NOT_ENABLED')
              ? 'We could not send the code. Please try again.'
              : 'We could not send the verification code. Please try again.';
          setState(() {
            _phoneHasError = true;
            _phoneMessage = msg;
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
                _currentStep = 5;
              });
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
    VoidCallback? onContinue,
  }) async {
    if (!mounted) return;
    const Color primaryColor = Color(0xFFF4B63D);
    await showDialog(
      context: context,
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
                onContinue?.call();
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
        setState(() => _currentStep = 0);
        return;
      }

      final pwdMsg = _passwordStrength(pwd);
      if (pwdMsg != null) {
        _showSnack(pwdMsg);
        setState(() => _currentStep = 1);
        return;
      }

      if (_verificationId == null) {
        _showSnack('Please request and enter the verification code first.');
        setState(() {
          _currentStep = 5;
          _otpError = 'Enter the code sent to your phone.';
        });
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
        setState(() {
          _otpError = e.message ?? 'Invalid code. Please try again.';
          _otpSent = true;
        });
        return;
      }

        final res = await _authService.registerUser(
          name: fullName,
          email: email,
          password: pwd,
          role: _selectedRole ?? 'client',
          phone: _fullPhoneNumber,
          defaultAddress: _addressCtrl.text.trim(),
        );

      if (res == null) {
        _showSnack('Failed to register');
        return;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final caregiverRef =
          FirebaseFirestore.instance.collection('caregivers').doc(uid);
      final extras = <String, dynamic>{
        'servicePreferences': _selectedServices,
        'phoneVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'caregiver') {
        extras['rating'] = 0.0;
        await caregiverRef.update(extras);
      } else {
        await userRef.update(extras);
      }

      if (!mounted) return;
      final Widget destination;
      if (res is CaregiverModel) {
        destination = const CaregiverRootScreen();
      } else if (res is UserModel) {
        destination = const UserRootScreen();
      } else {
        destination = const TouchdownScreen();
      }
      await _showDialogMessage(
        title: 'Registration Successful',
        message: 'Your ElderAssist account is ready.',
        buttonText: 'Login',
        onContinue: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => destination),
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
            MaterialPageRoute(builder: (_) => const TouchdownScreen()),
            (route) => false,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildRoleStep();
      case 1:
        return _buildAccountStep();
      case 2:
        return _buildServiceStep();
      case 3:
        return _buildLocationStep();
      case 4:
        return _buildPhoneStep();
      case 5:
        return _buildOtpStep();
      default:
        return const SizedBox.shrink();
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
              onTap: () => setState(() => _selectedRole = 'user'),
            ),
            _roleOption(
              title: 'Caregiver',
              subtitle: 'Provide professional support',
              icon: Icons.medical_services_outlined,
              isSelected: _selectedRole == 'caregiver',
              onTap: () => setState(() => _selectedRole = 'caregiver'),
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
        const Text(
          'Password must be at least 8 characters.',
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
        const Text(
          'Service preferences',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select at least one service preference.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kServiceOptions.map((service) {
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
                    if (!_mapControllerCompleter.isCompleted) {
                      _mapControllerCompleter.complete(controller);
                    }
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
              final number = phone.number.trim();
              setState(() {
                _fullPhoneNumber = number.isEmpty ? '' : phone.completeNumber;
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
            if (_currentStep != 5) return null;
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
    if (_currentStep == 4) return 'Send verification code';
    if (_isLastStep) return 'Create account';
    return 'Continue';
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _isCurrentStepReady() &&
        !_isRegistering &&
        !_isSendingCode &&
        !_isCheckingEmail &&
        !(_currentStep == 4 && _otpCooldownSeconds > 0);
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
                          (_currentStep == 3 ||
                              _currentStep == 4 ||
                              _currentStep == 5)
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
    switch (_currentStep) {
      case 0:
        return 'Choose your role';
      case 1:
        return 'Let\'s create your account';
      case 2:
        return 'Service preferences';
      case 3:
        return 'Confirm your location';
      case 4:
        return 'Verify your phone number';
      case 5:
        return 'Enter the verification code';
      default:
        return '';
    }
  }

  String get _stepSubtitle {
    switch (_currentStep) {
      case 0:
        return 'Tell us whether you are requesting care or providing it.';
      case 1:
        return 'Share your details so we can secure your account.';
      case 2:
        return 'Select the services that best describe your needs.';
      case 3:
        return 'We use your location to match nearby caregivers.';
      case 4:
        return 'We\'ll contact you for ElderAssist services.';
      case 5:
        return 'Check your SMS inbox for the 6-digit code.';
      default:
        return '';
    }
  }
}
