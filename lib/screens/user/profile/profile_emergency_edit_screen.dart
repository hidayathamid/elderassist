import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:uuid/uuid.dart';
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
const List<String> _relationshipOptions = [
  'Sibling',
  'Friend',
  'Doctor',
  'Other',
];

class ProfileEmergencyEditScreen extends StatefulWidget {
  const ProfileEmergencyEditScreen({super.key, this.contactId});

  final String? contactId;

  @override
  State<ProfileEmergencyEditScreen> createState() =>
      _ProfileEmergencyEditScreenState();
}

class _ProfileEmergencyEditScreenState
    extends State<ProfileEmergencyEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pairingLinkCtrl = TextEditingController();
  String _relationship = 'Sibling';
  bool _loading = true;
  final _picker = ImagePicker();
  bool _uploadingPhoto = false;
  String? _photoUrl;
  String _fullPhoneNumber = '';
  bool _dirty = false;
  bool _isSubmitting = false;
  bool _isInitializing = true;
  String _selectedDialCode = '+60';
  String _currentCountryCode = 'MY';
  static final List<Country> _dialCodeCountries = [...countries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  final Uuid _uuid = const Uuid();
  bool _isGeneratingLink = false;
  String? _currentPairCode;
  String? _currentPairingLink;
  final LayerLink _relationshipFieldLink = LayerLink();
  final GlobalKey _relationshipFieldKey = GlobalKey();
  OverlayEntry? _relationshipOverlayEntry;
  final TextEditingController _relationshipFieldController =
      TextEditingController();
  final TextEditingController _customRelationshipCtrl = TextEditingController();
  bool get _canSave =>
      !_loading && !_isSubmitting && _dirty && _hasRequiredValues;
  bool get _canGeneratePairLink =>
      !_loading && !_isGeneratingLink && widget.contactId != null;

  void _markDirty() {
    if (_isInitializing || _dirty) return;
    setState(() => _dirty = true);
  }

  bool get _hasRequiredValues {
    return _nameController.text.trim().isNotEmpty &&
        _fullPhoneNumber.trim().isNotEmpty;
  }

  List<Map<String, dynamic>> _extractEmergencyList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['emergencyContacts'] ?? data['emergencyContact'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_markDirty);
    _phoneController.addListener(_markDirty);
    _customRelationshipCtrl.addListener(() {
      if (_relationship == 'Other') {
        final text = _customRelationshipCtrl.text.trim();
        _relationshipFieldController.text = text.isNotEmpty ? text : 'Other';
      }
      _markDirty();
    });
    _relationshipFieldController.text = _relationship;
    _loadContact();
  }

  Future<void> _loadContact() async {
    _isInitializing = true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isInitializing = false;
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final contacts = _extractEmergencyList(doc.data());
    if (widget.contactId != null) {
      final match = contacts.firstWhere(
        (entry) => entry['id'] == widget.contactId,
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        _nameController.text = match['name'] as String? ?? '';
        final phone = match['phone']?.toString() ?? '';
        final matchedDial = _normalizeDialCode(_detectDialCodeFromPhone(phone));
        _selectedDialCode = matchedDial.isNotEmpty ? matchedDial : '+60';
        _currentCountryCode = _countryCodeFromDialCode(_selectedDialCode);
        final national = phone.isNotEmpty
            ? _stripDialCode(phone, _selectedDialCode)
            : '';
        _phoneController.text = national;
        _fullPhoneNumber = national.isNotEmpty
            ? '$_selectedDialCode$national'
            : '';
        _fullPhoneNumber = _collapseRepeatedDialPrefix(
          _fullPhoneNumber,
          _selectedDialCode,
        );
        final rawRelationship =
            (match['relationship'] as String?)?.trim() ?? '';
        if (_relationshipOptions.contains(rawRelationship) &&
            rawRelationship != 'Other') {
          _relationship = rawRelationship;
          _customRelationshipCtrl.clear();
          _relationshipFieldController.text = rawRelationship;
        } else if (rawRelationship.isNotEmpty) {
          _relationship = 'Other';
          _customRelationshipCtrl.text = rawRelationship;
          _relationshipFieldController.text = rawRelationship;
        } else {
          _relationship = 'Sibling';
          _customRelationshipCtrl.clear();
          _relationshipFieldController.text = 'Sibling';
        }
        _currentPairCode = match['pairCode'] as String?;
        final entryPhoto = match['photoUrl']?.toString();
        if (entryPhoto?.isNotEmpty ?? false) {
          _photoUrl = entryPhoto;
        }
        if (_currentPairCode?.isNotEmpty ?? false) {
          _currentPairingLink = _pairingDeepLink(_currentPairCode!);
          _pairingLinkCtrl.text = _currentPairingLink!;
        } else {
          _currentPairingLink = null;
          _pairingLinkCtrl.clear();
        }
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
    _isInitializing = false;
  }

  Future<void> _saveAndClose() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_loading) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final doc = await userRef.get();
    final contacts = _extractEmergencyList(doc.data());

    final entryId = widget.contactId ?? _uuid.v4();
    final dialSegment = _normalizeDialCode(_selectedDialCode);
    var phoneValue = _fullPhoneNumber.trim().isNotEmpty
        ? _collapseRepeatedDialPrefix(_fullPhoneNumber.trim(), dialSegment)
        : '';
    if (phoneValue.isEmpty) {
      final rawPhone = _phoneController.text.trim();
      final normalized = rawPhone.isNotEmpty
          ? _stripDialCode(rawPhone, dialSegment)
          : '';
      phoneValue = normalized.isNotEmpty
          ? '$dialSegment$normalized'
          : rawPhone.replaceAll(RegExp('[^0-9+]'), '');
      phoneValue = _collapseRepeatedDialPrefix(phoneValue, dialSegment);
    }
    final entryPhoto = _photoUrl?.isNotEmpty == true ? _photoUrl : null;
    final relationshipValue = _relationship == 'Other'
        ? (_customRelationshipCtrl.text.trim().isNotEmpty
              ? _customRelationshipCtrl.text.trim()
              : 'Other')
        : _relationship;
    final data = {
      'id': entryId,
      'name': _nameController.text.trim(),
      'phone': phoneValue,
      'relationship': relationshipValue,
      if (entryPhoto != null) 'photoUrl': entryPhoto,
    };

    final index = contacts.indexWhere(
      (entry) => entry['id'] == widget.contactId,
    );
    if (index != -1) {
      contacts[index] = {...contacts[index], ...data};
    } else {
      contacts.add(data);
    }

    setState(() => _isSubmitting = true);
    try {
      await userRef.update({'emergencyContacts': contacts});
      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save contact.')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPairingLink = _currentPairingLink?.isNotEmpty == true;
    final bool canGeneratePairingLink = _canGeneratePairLink;
    final bool contactSaved = widget.contactId != null;
    final VoidCallback? telegramButtonAction = hasPairingLink
        ? _copyPairingLink
        : (canGeneratePairingLink ? _generatePairingLink : null);
    final Color telegramButtonColor = hasPairingLink
        ? Colors.blue
        : (canGeneratePairingLink ? _tealAccent : Colors.grey.shade300);
    final String telegramHelperText = contactSaved
        ? 'Share this code so the contact can connect through Telegram.'
        : 'Save contact before generating Telegram access';
    return WillPopScope(
      onWillPop: () async => _handleBackPress(),
      child: Scaffold(
        backgroundColor: Colors.white,
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
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileDarkText,
              size: 20,
            ),
            onPressed: () => _handleBackPress(),
          ),
          title: const Text(
            'Add Emergency Contact',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildAvatarPicker(),
                                const SizedBox(height: 16),
                                _labeledField(
                                  label: 'Name',
                                  helperText: null,
                                  child: _buildTextInput(
                                    controller: _nameController,
                                    hint: 'Full name',
                                    onChanged: (_) => _markDirty(),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Provide a name.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _labeledField(
                                  label: 'Relationship',
                                  helperText: null,
                                  child: _relationshipSelector(),
                                ),
                                const SizedBox(height: 10),
                                _buildPhoneField(),
                                const SizedBox(height: 12),
                                const Text(
                                  'Telegram pairing link',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: _profileDarkText,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _pairingLinkCtrl,
                                  readOnly: true,
                                  showCursor: false,
                                  style: _inputFieldTextStyle,
                                  decoration: InputDecoration(
                                    hintText: 'Generate pairing link',
                                    hintStyle: _inputFieldHintStyle,
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(16),
                                      ),
                                      borderSide: BorderSide(
                                        color: _profileDarkText,
                                        width: 1.1,
                                      ),
                                    ),
                                    suffixIconConstraints: const BoxConstraints(
                                      minWidth: 90,
                                    ),
                                    suffixIcon: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        height: 32,
                                        child: ElevatedButton(
                                          onPressed: _isGeneratingLink
                                              ? null
                                              : telegramButtonAction,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                telegramButtonColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: _isGeneratingLink
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : Text(
                                                  hasPairingLink
                                                      ? 'Copy'
                                                      : 'Generate',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  telegramHelperText,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _canSave ? _saveAndClose : null,
                            style: _primaryButtonStyle(),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomRight,
              children: [
                DefaultProfileAvatar(
                  radius: 40,
                  photoUrl: _photoUrl,
                  label: _contactAvatarLabel(),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: InkWell(
                    onTap: _uploadingPhoto ? null : _pickPhoto,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _accentGold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _uploadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: Colors.black87,
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
            const SizedBox(height: 6),
            const Text(
              'Add or update photo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required Widget child,
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
        child,
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

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
        "emergency-photos/$uid/${_uuid.v4()}.jpg",
      );
      await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg"));
      final downloadUrl = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _photoUrl = downloadUrl;
        _dirty = true;
      });
    } catch (e) {
      _showSnack('Unable to upload photo: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: _inputFieldTextStyle,
      onChanged: onChanged,
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

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone number',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
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
          ),
          child: IntlPhoneField(
            key: ValueKey(_currentCountryCode),
            controller: _phoneController,
            initialCountryCode: _currentCountryCode,
            disableLengthCheck: true,
            pickerDialogStyle: PickerDialogStyle(
              backgroundColor: Colors.white,
              countryNameStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              searchFieldInputDecoration: InputDecoration(
                hintText: 'Search country',
                hintStyle: const TextStyle(color: Colors.black54),
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide(color: Colors.black87, width: 1.1),
                ),
              ),
            ),
            decoration: InputDecoration(
              hintText: 'Enter phone number',
              hintStyle: _inputFieldHintStyle,
              suffixIcon: const SizedBox.shrink(),
            ),
            style: _inputFieldTextStyle,
            dropdownIcon: const Icon(Icons.expand_more, size: 18),
            validator: (_) {
              if (_fullPhoneNumber.trim().isEmpty) {
                return 'Provide a phone number.';
              }
              return null;
            },
            showDropdownIcon: true,
            onChanged: (phone) {
              final normalizedDial = _normalizeDialCode(
                '+${phone.countryCode}',
              );
              final national = phone.number.isNotEmpty
                  ? _stripDialCode(phone.completeNumber, normalizedDial)
                  : '';
              final candidate = national.isNotEmpty
                  ? '$normalizedDial$national'
                  : '';
              setState(() {
                _selectedDialCode = normalizedDial;
                _currentCountryCode = phone.countryISOCode;
                _fullPhoneNumber = _collapseRepeatedDialPrefix(
                  candidate,
                  normalizedDial,
                );
              });
              _markDirty();
            },
            onCountryChanged: (country) {
              final normalizedDial = _normalizeDialCode('+${country.dialCode}');
              final nationalInput = _phoneController.text.trim();
              final normalized = nationalInput.isNotEmpty
                  ? _stripDialCode(nationalInput, normalizedDial)
                  : '';
              if (normalized != nationalInput) {
                _phoneController.text = normalized;
              }
              setState(() {
                _selectedDialCode = normalizedDial;
                _currentCountryCode = country.code;
                final candidate = normalized.isNotEmpty
                    ? '$normalizedDial$normalized'
                    : '';
                _fullPhoneNumber = _collapseRepeatedDialPrefix(
                  candidate,
                  normalizedDial,
                );
              });
              _markDirty();
            },
          ),
        ),
      ],
    );
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
    return sanitized.startsWith('0') ? sanitized.substring(1) : sanitized;
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

  String _countryCodeFromDialCode(String dialCode) {
    final digits = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    for (final country in countries) {
      if (country.dialCode == digits) {
        return country.code;
      }
    }
    return 'MY';
  }

  void _returnToPrevious() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
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

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) {
      _returnToPrevious();
    }
    return false;
  }

  Future<void> _generatePairingLink() async {
    if (!_canGeneratePairLink || widget.contactId == null) return;
    setState(() {
      _isGeneratingLink = true;
    });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateTelegramPairCode',
      );
      final result = await callable.call(<String, dynamic>{
        'role': 'role4',
        'contactId': widget.contactId,
      });
      final data = result.data;
      if (data is Map<String, dynamic>) {
        final link = (data['telegramLink'] as String?)?.trim();
        final pairCode = (data['pairCode'] as String?)?.trim();
        if (link != null && link.isNotEmpty) {
          if (mounted) {
            setState(() {
              _currentPairingLink = link;
              _currentPairCode = pairCode ?? _currentPairCode;
              _pairingLinkCtrl.text = link;
            });
            // link now displayed in field and copy button available; skip dialog
          }
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate pairing link.')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Unable to generate pairing link.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to generate pairing link. ${error.toString()}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingLink = false);
    }
  }

  Future<void> _copyPairingLink() async {
    final link = _currentPairingLink;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
  }

  String _pairingDeepLink(String pairCode) =>
      'https://t.me/Elder_AssistBot?start=$pairCode';

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _relationshipSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _relationshipFieldLink,
          child: TextFormField(
            key: _relationshipFieldKey,
            controller: _relationshipFieldController,
            readOnly: true,
            showCursor: false,
            style: _inputFieldTextStyle,
            decoration: InputDecoration(
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
              suffixIcon: const Icon(Icons.expand_more, size: 18),
            ),
            onTap: _toggleRelationshipMenu,
          ),
        ),
        if (_relationship == 'Other') ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _customRelationshipCtrl,
            style: _inputFieldTextStyle,
            decoration: InputDecoration(
              hintText: 'Specify relationship',
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
          ),
        ],
      ],
    );
  }

  void _toggleRelationshipMenu() {
    if (_relationshipOverlayEntry != null) {
      _closeRelationshipMenu();
      return;
    }
    _showRelationshipMenu();
  }

  void _showRelationshipMenu() {
    final overlay = Overlay.of(context);
    final renderBox =
        _relationshipFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    _relationshipOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeRelationshipMenu,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 6,
              width: size.width,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _relationshipOptions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final option = _relationshipOptions[index];
                      final selected = option == _relationship;
                      return InkWell(
                        onTap: () => _selectRelationship(option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                option,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_relationshipOverlayEntry!);
  }

  void _selectRelationship(String option) {
    setState(() {
      _relationship = option;
      if (option == 'Other') {
        final custom = _customRelationshipCtrl.text.trim();
        _relationshipFieldController.text = custom.isNotEmpty
            ? custom
            : 'Other';
      } else {
        _customRelationshipCtrl.clear();
        _relationshipFieldController.text = option;
      }
    });
    _markDirty();
    _closeRelationshipMenu();
  }

  void _closeRelationshipMenu() {
    _relationshipOverlayEntry?.remove();
    _relationshipOverlayEntry = null;
  }

  String _contactAvatarLabel() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name;
    return 'Contact';
  }

  ButtonStyle _primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return _dirty
              ? const Color(0xFFF4B63D).withAlpha(230)
              : Colors.grey.shade300;
        }
        return _accentGold;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return _dirty ? Colors.black87 : Colors.grey.shade600;
        }
        return Colors.black;
      }),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0;
        return 2;
      }),
    );
  }

  @override
  void dispose() {
    _closeRelationshipMenu();
    _relationshipFieldController.dispose();
    _customRelationshipCtrl.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _pairingLinkCtrl.dispose();
    super.dispose();
  }
}
