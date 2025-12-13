import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const TextStyle _inputFieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
final TextStyle _inputFieldHintStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText.withValues(alpha: 0.45),
);

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _picker = ImagePicker();

  static final List<Country> _dialCodeCountries = [...countries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));

  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _hasChanges = false;
  String _initialName = "";
  String _initialEmail = "";
  String _initialPhone = "";
  String _initialPhoneFull = "";
  String? _emailError;
  String? _phoneError;
  String? _nameError;
  String _selectedDialCode = '+60';
  String _currentCountryCode = 'MY';
  String _fullPhoneNumber = "";
  bool get _canSave =>
      _hasChanges &&
      !_saving &&
      _firstNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _nameError == null &&
      _emailError == null &&
      _phoneError == null;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _loadProfile();
  }

  void _onFieldChanged() {
    final name = _firstNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final dialSegment = _normalizeDialCode(_selectedDialCode);
    final national = phone.isNotEmpty ? _stripDialCode(phone, dialSegment) : '';
    final candidate = national.isNotEmpty ? '$dialSegment$national' : '';
    _fullPhoneNumber = _collapseRepeatedDialPrefix(candidate, dialSegment);
    final dirty =
        name != _initialName ||
        email != _initialEmail ||
        _fullPhoneNumber != _initialPhoneFull;
    final emailLower = email.toLowerCase();
    final emailError = email.isEmpty
        ? "Email is required"
        : (!emailLower.endsWith('@gmail.com') ||
                  emailLower.length <= '@gmail.com'.length
              ? "Email must end with @gmail.com"
              : null);
    final nameError = name.isEmpty ? "Name is required" : null;
    final phoneError = phone.isEmpty ? "Phone is required" : null;
    final dialError = _validatePhoneMatch();
    if (dirty != _hasChanges ||
        emailError != _emailError ||
        nameError != _nameError ||
        dialError != _phoneError) {
      setState(() {
        _hasChanges = dirty;
        _emailError = emailError;
        _nameError = nameError;
        _phoneError = dialError ?? phoneError;
      });
    }
  }

  String _normalizeNationalNumber(String value) {
    return value.startsWith('0') ? value.substring(1) : value;
  }

  String? _validatePhoneMatch() {
    final digits = _phoneController.text.trim();
    if (digits.isEmpty || _fullPhoneNumber.trim().isEmpty) {
      return "Phone is required";
    }
    final plainFull = _fullPhoneNumber.replaceFirst('+', '');
    final dialTrim = _selectedDialCode.replaceFirst('+', '');
    if (dialTrim.isNotEmpty && !plainFull.startsWith(dialTrim)) {
      return "Verify the first digits against the country selected";
    }
    if (plainFull.length >= 4) {
      final prefix4 = plainFull.substring(0, 4);
      if (dialTrim.isNotEmpty && !prefix4.startsWith(dialTrim)) {
        return "Verify the first digits against the country selected";
      }
    }
    return null;
  }

  String _countryCodeFromDialCode(String dialCode) {
    final digits = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    for (final country in countries) {
      if (country.dialCode == digits) {
        return country.code;
      }
    }
    return 'MY';
  }

  String _detectDialCodeFromPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return _selectedDialCode;
    for (final country in _dialCodeCountries) {
      final plusDial = '+${country.dialCode}';
      if (trimmed.startsWith(plusDial)) return plusDial;
      final zeroDial = '00${country.dialCode}';
      if (trimmed.startsWith(zeroDial)) return '+${country.dialCode}';
    }
    return _selectedDialCode;
  }

  String _stripDialCode(String value, String dialCode) {
    var sanitized = value.trim();
    if (sanitized.isEmpty) return '';
    final normalizedDial = dialCode.startsWith('+') ? dialCode : '+$dialCode';
    final dialDigits = normalizedDial.replaceAll('+', '');
    final zeroDial = dialDigits.isNotEmpty ? '00$dialDigits' : '';

    sanitized = sanitized.replaceAll(RegExp(r'[^0-9+]'), '');

    while (sanitized.startsWith('+')) {
      if (normalizedDial.length > 1 && sanitized.startsWith(normalizedDial)) {
        sanitized = sanitized.substring(normalizedDial.length);
        continue;
      }
      sanitized = sanitized.substring(1);
    }

    if (zeroDial.isNotEmpty) {
      while (sanitized.startsWith(zeroDial)) {
        sanitized = sanitized.substring(zeroDial.length);
      }
    }

    while (dialDigits.isNotEmpty && sanitized.startsWith(dialDigits)) {
      sanitized = sanitized.substring(dialDigits.length);
    }

    sanitized = sanitized.replaceAll(RegExp(r'[^0-9]'), '');
    return _normalizeNationalNumber(sanitized);
  }

  String _normalizeDialCode(String dialCode) {
    var sanitized = dialCode.trim();
    if (sanitized.isEmpty) return '';
    final hadPlus = sanitized.contains('+');
    sanitized = sanitized.replaceAll(RegExp(r'[^0-9]'), '');
    if (sanitized.isEmpty) return '';
    return hadPlus ? '+$sanitized' : sanitized;
  }

  String _collapseRepeatedDialPrefix(String value, String dialSegment) {
    if (value.isEmpty || dialSegment.isEmpty) return value;
    var normalized = value;
    while (normalized.startsWith('$dialSegment$dialSegment')) {
      normalized = normalized.substring(dialSegment.length);
    }
    final dialDigits = dialSegment.replaceAll('+', '');
    if (dialDigits.isNotEmpty) {
      while (normalized.startsWith('$dialDigits$dialDigits')) {
        normalized = normalized.substring(dialDigits.length);
      }
    }
    return normalized;
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();
    if (!snap.exists) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final data = snap.data()!;
    final name = data["name"] as String? ?? "";
    final fragments = name.split(" ");
    _firstNameController.text = fragments.isNotEmpty ? fragments.first : "";
    _emailController.text = data["email"] as String? ?? "";
    final phoneRaw = data["phone"] as String? ?? "";
    final matchedDial = _normalizeDialCode(_detectDialCodeFromPhone(phoneRaw));
    _selectedDialCode = matchedDial;
    _currentCountryCode = _countryCodeFromDialCode(matchedDial);
    final national = phoneRaw.isNotEmpty
        ? _stripDialCode(phoneRaw, matchedDial)
        : '';
    _phoneController.text = national;
    _fullPhoneNumber = national.isNotEmpty ? '$matchedDial$national' : '';
    _fullPhoneNumber = _collapseRepeatedDialPrefix(
      _fullPhoneNumber,
      matchedDial,
    );
    _photoUrl = data["photoUrl"] as String?;

    if (mounted) {
      setState(() {
        _loading = false;
        _initialName = _firstNameController.text.trim();
        _initialEmail = _emailController.text.trim();
        _initialPhone = _phoneController.text.trim();
        _initialPhoneFull = _fullPhoneNumber;
        _hasChanges = false;
        _emailError = null;
        _nameError = null;
        _phoneError = null;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
        "users/$uid/profile_photo.jpg",
      );
      await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg"));
      final downloadUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection("users").doc(uid).update({
        "photoUrl": downloadUrl,
      });
      setState(() {
        _photoUrl = downloadUrl;
        _hasChanges = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Unable to upload photo")));
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  String _profileAvatarLabel() {
    final firstName = _firstNameController.text.trim();
    if (firstName.isNotEmpty) return firstName;
    final email = _emailController.text.trim();
    if (email.isNotEmpty) return email;
    return 'User';
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firstName = _firstNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (firstName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        _emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fix the highlighted fields")),
      );
      return;
    }

    setState(() => _saving = true);

    final dialSegment = _normalizeDialCode(_selectedDialCode);
    var phoneToSave = _fullPhoneNumber.trim().isNotEmpty
        ? _collapseRepeatedDialPrefix(_fullPhoneNumber.trim(), dialSegment)
        : '';
    if (phoneToSave.isEmpty) {
      final normalized = phone.isNotEmpty
          ? _stripDialCode(phone, dialSegment)
          : '';
      phoneToSave = normalized.isNotEmpty
          ? '$dialSegment$normalized'
          : phone.replaceAll(RegExp('[^0-9+]'), '');
      phoneToSave = _collapseRepeatedDialPrefix(phoneToSave, dialSegment);
    }

    try {
      await FirebaseFirestore.instance.collection("users").doc(uid).update({
        "name": firstName,
        "email": email,
        "phone": phoneToSave,
      });

      if (!mounted) return;

      setState(() {
        _initialName = firstName;
        _initialEmail = email;
        _initialPhone = phone;
        _hasChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile saved successfully"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _returnToOverview();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to save profile: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _returnToOverview() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          "Discard changes?",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          "You have unsaved changes. Leave anyway?",
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
                    "Cancel",
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
                    backgroundColor: const Color(0xFFF4B63D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text("Discard"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) {
      _returnToOverview();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldLeave = await _handleBackPress();
        return shouldLeave;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: true,
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
            "Edit Profile",
            style: TextStyle(color: _profileDarkText),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.bottomRight,
                                children: [
                DefaultProfileAvatar(
                  radius: 40,
                  photoUrl: _photoUrl,
                  label: _profileAvatarLabel(),
                ),
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: InkWell(
                                      onTap: _uploadingPhoto
                                          ? null
                                          : _pickPhoto,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: _accentGold,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: _uploadingPhoto
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.photo_camera,
                                                size: 16,
                                                color: Colors.black87,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _inputWithLabel(
                              label: "Full Name",
                              controller: _firstNameController,
                              hint: "Full Name",
                              helperText: _nameError,
                            ),
                            const SizedBox(height: 10),
                            _inputWithLabel(
                              label: "Email",
                              controller: _emailController,
                              hint: "Email",
                              keyboardType: TextInputType.emailAddress,
                              helperText: _emailError,
                            ),
                            const SizedBox(height: 10),
                            _phoneField(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canSave ? _saveProfile : null,
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return _hasChanges
                                    ? _accentGold.withOpacity(0.8)
                                    : Colors.grey.shade300;
                              }
                              return _accentGold;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return _hasChanges
                                    ? Colors.black87
                                    : Colors.grey.shade600;
                              }
                              return Colors.black;
                            }),
                            elevation: WidgetStateProperty.resolveWith<double>((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return 0;
                              }
                              return 2;
                            }),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  "Save",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: _inputFieldTextStyle,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _inputFieldHintStyle,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
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
      ),
    );
  }

  Widget _inputWithLabel({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        _buildTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType,
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6),
            child: Text(
              helperText,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Phone Number",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        IntlPhoneField(
          key: ValueKey(_currentCountryCode),
          controller: _phoneController,
          initialCountryCode: _currentCountryCode,
          disableLengthCheck: true,
          decoration: InputDecoration(
            hintText: "123 4567 890",
            hintStyle: const TextStyle(color: Colors.black38),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.black87,
                width: 1.2,
              ),
            ),
            errorText: _phoneError,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            prefixStyle: const TextStyle(
              fontSize: 0,
              height: 0,
              color: Colors.transparent,
            ),
          ),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
          dropdownIcon: const Icon(Icons.expand_more, size: 18),
          showDropdownIcon: true,
          onChanged: (_) => _onFieldChanged(),
          onCountryChanged: (country) {
            _selectedDialCode = _normalizeDialCode('+${country.dialCode}');
            _currentCountryCode = country.code;
            final nationalInput = _phoneController.text.trim();
            final normalized = nationalInput.isNotEmpty
                ? _stripDialCode(nationalInput, _selectedDialCode)
                : '';
            if (normalized != nationalInput) {
              _phoneController.text = normalized;
            }
            _onFieldChanged();
          },
        ),
      ],
    );
  }
}
