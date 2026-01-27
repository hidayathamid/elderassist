import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../widgets/default_profile_avatar.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const TextStyle _inputFieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
final TextStyle _inputFieldHintStyle = TextStyle(
  fontSize: 12,
  color: _profileDarkText.withValues(alpha: 0.45),
  fontWeight: FontWeight.w600,
);

const List<String> _perOptions = ['trip', 'hour', 'visit', 'session'];

class AdminReviewsEditScreen extends StatefulWidget {
  const AdminReviewsEditScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  State<AdminReviewsEditScreen> createState() => _AdminReviewsEditScreenState();
}

class _AdminReviewsEditScreenState extends State<AdminReviewsEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _perFieldController = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final Uuid _uuid = const Uuid();
  String? _photoUrl;
  String _selectedPer = 'hour';

  bool _isSubmitting = false;
  bool _isInitializing = true;
  bool _dirty = false;
  bool _uploadingPhoto = false;

  final LayerLink _perFieldLink = LayerLink();
  final GlobalKey _perFieldKey = GlobalKey();
  OverlayEntry? _perOverlayEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
    _nameCtrl.addListener(_markDirty);
    _priceCtrl.addListener(_markDirty);
    _perFieldController.text = _selectedPer;
    _descriptionCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _closePerMenu();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _perFieldController.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_isInitializing || _dirty) return;
    setState(() => _dirty = true);
  }

  bool get _hasRequiredValues {
    final name = _nameCtrl.text.trim();
    final price = _parsePrice(_priceCtrl.text);
    return name.isNotEmpty && price != null;
  }

  double? _parsePrice(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    trimmed = trimmed.toUpperCase().replaceAll('RM', '').trim();
    var sanitized = trimmed.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (sanitized.isEmpty) return null;

    final hasDot = sanitized.contains('.');
    final hasComma = sanitized.contains(',');
    if (hasDot && hasComma) {
      // Treat the last separator as the decimal separator.
      final lastDot = sanitized.lastIndexOf('.');
      final lastComma = sanitized.lastIndexOf(',');
      if (lastDot > lastComma) {
        sanitized = sanitized.replaceAll(',', '');
      } else {
        sanitized = sanitized.replaceAll('.', '');
        sanitized = sanitized.replaceAll(',', '.');
      }
    } else if (hasComma && !hasDot) {
      sanitized = sanitized.replaceAll(',', '.');
    }

    return double.tryParse(sanitized);
  }

  Future<void> _initialize() async {
    _isInitializing = true;
    try {
      final id = (widget.serviceId ?? '').trim();
      if (id.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('services')
          .doc(id)
          .get();
      final data = doc.data();
      if (data == null) return;
      _nameCtrl.text = (data['name'] as String?)?.trim() ?? '';
      final price = (data['price'] as num?)?.toDouble();
      _priceCtrl.text = price == null ? '' : price.toStringAsFixed(2);
      final per = (data['per'] as String?)?.trim().toLowerCase() ?? '';
      if (_perOptions.contains(per)) {
        _selectedPer = per;
        _perFieldController.text = per;
      }
      _descriptionCtrl.text = (data['description'] as String?)?.trim() ?? '';
      _photoUrl = (data['imageUrl'] as String?)?.trim();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _dirty = false;
        });
      }
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

  Future<void> _maybePopWithDiscard() async {
    final ok = await _confirmDiscard();
    if (!ok || !mounted) return;
    setState(() => _dirty = false);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1200,
    );
    if (picked == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      _showSnack('Please sign in to upload an image.');
      return;
    }
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
        "service-photos/$uid/${_uuid.v4()}.jpg",
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

  Future<void> _saveService() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please sign in to continue.');
      return;
    }
    final name = _nameCtrl.text.trim();
    final price = _parsePrice(_priceCtrl.text);
    if (price == null) {
      _showSnack('Provide a valid price.');
      return;
    }
    final description = _descriptionCtrl.text.trim();

    setState(() => _isSubmitting = true);
    try {
      final ref = FirebaseFirestore.instance.collection('services');
      final serviceId = (widget.serviceId ?? '').trim();
      final docRef = serviceId.isEmpty ? ref.doc() : ref.doc(serviceId);
      final payload = <String, dynamic>{
        'name': name,
        'price': price,
        'per': _selectedPer,
        'description': description,
        'imageUrl': (_photoUrl ?? '').trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (serviceId.isEmpty) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = user.uid;
      }
      await docRef.set(payload, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Unable to save service: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = !_isSubmitting && _hasRequiredValues;
    final title = (widget.serviceId ?? '').trim().isEmpty
        ? 'Add Service'
        : 'Edit Service';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _maybePopWithDiscard();
      },
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
            onPressed: _maybePopWithDiscard,
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: SafeArea(
          child: _isInitializing
              ? const Center(child: CircularProgressIndicator())
              : Form(
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
                                  controller: _nameCtrl,
                                  hintText: 'Service name',
                                  validator: (value) {
                                    if (value == null ||
                                        value.trim().isEmpty) {
                                      return 'Provide a name.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                _labeledField(
                                  label: 'Price',
                                  controller: _priceCtrl,
                                  hintText: 'e.g. 120.00',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^[0-9]*[.,]?[0-9]{0,2}$'),
                                    ),
                                  ],
                                  validator: (value) {
                                    if (value == null ||
                                        value.trim().isEmpty) {
                                      return 'Provide a price.';
                                    }
                                    if (_parsePrice(value) == null) {
                                      return 'Enter a valid price.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                _perSelector(),
                                const SizedBox(height: 8),
                                _labeledField(
                                  label: 'Descriptions',
                                  controller: _descriptionCtrl,
                                  hintText: 'Write a short description',
                                  maxLines: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canSubmit ? _saveService : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  canSubmit ? _accentGold : Colors.grey[300],
                              foregroundColor:
                                  canSubmit ? Colors.black : Colors.white70,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              elevation: canSubmit ? 2 : 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
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
    final label = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'S';
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
                  label: label,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: InkWell(
                    onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
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
              'Upload profile photo',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: _profileDarkText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: _inputFieldTextStyle,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: _inputFieldHintStyle,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
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
              borderSide: BorderSide(color: _profileDarkText, width: 1.1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _perSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Per',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _perFieldLink,
          child: TextFormField(
            key: _perFieldKey,
            controller: _perFieldController,
            readOnly: true,
            showCursor: false,
            style: _inputFieldTextStyle,
            decoration: InputDecoration(
              hintText: 'Select per',
              hintStyle: _inputFieldHintStyle,
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
              suffixIcon: const Icon(Icons.expand_more, size: 18),
            ),
            onTap: _togglePerMenu,
            validator: (_) => null,
          ),
        ),
      ],
    );
  }

  void _togglePerMenu() {
    if (_perOverlayEntry != null) {
      _closePerMenu();
      return;
    }
    _showPerMenu();
  }

  void _showPerMenu() {
    final overlay = Overlay.of(context);
    final renderBox = _perFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    _perOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closePerMenu,
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
                    itemCount: _perOptions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final value = _perOptions[index];
                      final selected = value == _selectedPer;
                      return InkWell(
                        onTap: () => _selectPer(value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                value,
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
    overlay.insert(_perOverlayEntry!);
  }

  void _selectPer(String value) {
    setState(() {
      _selectedPer = value;
      _perFieldController.text = value;
      _dirty = true;
    });
    _closePerMenu();
  }

  void _closePerMenu() {
    _perOverlayEntry?.remove();
    _perOverlayEntry = null;
  }
}
