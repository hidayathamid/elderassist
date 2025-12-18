import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../ui_tokens.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _accentGold = Color(0xFFF4B63D);

const TextStyle _inputFieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
const TextStyle _inputFieldHintStyle = TextStyle(
  fontSize: 12,
  color: _profileDarkText60,
  fontWeight: FontWeight.w600,
);
const TextStyle _labelStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 12,
  color: _profileDarkText,
);

class ProfileDocumentsEditScreen extends StatefulWidget {
  const ProfileDocumentsEditScreen({super.key, this.documentId});

  final String? documentId;

  @override
  State<ProfileDocumentsEditScreen> createState() =>
      _ProfileDocumentsEditScreenState();
}

class _ProfileDocumentsEditScreenState
    extends State<ProfileDocumentsEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _fileNameCtrl = TextEditingController();
  final Uuid _uuid = const Uuid();

  Uint8List? _selectedFile;
  String? _selectedFileName;
  String? _existingFileName;
  String? _existingFileUrl;
  String? _existingStoragePath;

  bool _dirty = false;
  bool _isSaving = false;
  bool _allowProgrammaticPop = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_markDirty);
    _fileNameCtrl.addListener(_markDirty);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadExistingDocument(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_markDirty);
    _nameCtrl.dispose();
    _fileNameCtrl.removeListener(_markDirty);
    _fileNameCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _loadExistingDocument() async {
    if (widget.documentId == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('documents')
          .doc(widget.documentId)
          .get();
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (data['name'] as String?) ?? '';
        _existingFileName = (data['fileName'] as String?) ?? '';
        _fileNameCtrl.text = _existingFileName ?? '';
        _existingFileUrl = data['fileUrl'] as String?;
        _existingStoragePath = data['storagePath'] as String?;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pickFile() async {
    final XTypeGroup pdfGroup = const XTypeGroup(
      label: 'pdf',
      extensions: ['pdf'],
    );
    final XFile? picked = await openFile(
      acceptedTypeGroups: [pdfGroup],
      confirmButtonText: 'Select',
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() {
      _selectedFile = bytes;
      _selectedFileName = picked.name;
      _fileNameCtrl.text = picked.name;
      _dirty = true;
    });
  }

  bool get _canSave {
    return !_isSaving &&
        _dirty &&
        _nameCtrl.text.trim().isNotEmpty &&
        (_selectedFile != null || _existingFileUrl != null);
  }

  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate() || !_canSave) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);
    try {
      String? fileUrl = _existingFileUrl;
      String? storagePath = _existingStoragePath;
      if (_selectedFile != null) {
        final uploadPath = 'documents/${user.uid}/${_uuid.v4()}.pdf';
        final ref = FirebaseStorage.instance.ref(uploadPath);
        await ref.putData(
          _selectedFile!,
          SettableMetadata(contentType: 'application/pdf'),
        );
        fileUrl = await ref.getDownloadURL();
        if (storagePath != null && storagePath.isNotEmpty) {
          await FirebaseStorage.instance
              .ref(storagePath)
              .delete()
              .catchError((_) {});
        }
        storagePath = uploadPath;
      }
      final docId = widget.documentId ?? _uuid.v4();
      final fileNameValue = _fileNameCtrl.text.trim();
      final data = {
        'caregiverId': user.uid,
        'name': _nameCtrl.text.trim(),
        'fileName': fileNameValue,
        'status': false,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (storagePath != null) 'storagePath': storagePath,
        'updatedAt': FieldValue.serverTimestamp(),
        if (widget.documentId == null)
          'createdAt': FieldValue.serverTimestamp(),
      };
      final docRef = FirebaseFirestore.instance
          .collection('documents')
          .doc(docId);
      await docRef.set(data, SetOptions(merge: true));
      await _syncCaregiverDocumentReference(user.uid, docId);
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _dirty = false;
          _isSaving = false;
        });
      }
      await _showCompletionDialog();
      if (mounted) {
        _allowProgrammaticPop = true;
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Failed to save document. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _syncCaregiverDocumentReference(
    String caregiverId,
    String docId,
  ) async {
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId);
    final snapshot = await caregiverRef.get();
    final raw = snapshot.data()?['documents'];
    final List<Map<String, dynamic>> entries = [];
    if (raw is Iterable) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          entries.add(Map<String, dynamic>.from(item));
        } else if (item is Map) {
          entries.add(Map<String, dynamic>.from(item.cast()));
        }
      }
    }
    final updated = <Map<String, dynamic>>[];
    var replaced = false;
    for (final entry in entries) {
      if (entry['id'] == docId) {
        updated.add({'id': docId, 'name': _nameCtrl.text.trim()});
        replaced = true;
      } else {
        updated.add(entry);
      }
    }
    if (!replaced) {
      updated.add({'id': docId, 'name': _nameCtrl.text.trim()});
    }
    await caregiverRef.set({'documents': updated}, SetOptions(merge: true));
  }

  Future<void> _showCompletionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Document saved',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Your document has been uploaded.'),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          SizedBox(
            width: 170,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _handleBackPress() async {
    if (_allowProgrammaticPop) {
      _allowProgrammaticPop = false;
      return true;
    }
    if (!_dirty) return true;
    final result = await _confirmDiscard();
    return result;
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
          SizedBox(
            width: 120,
            child: OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
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
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _defaultDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: _inputFieldHintStyle,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiTokens.r16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiTokens.r16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: _profileDarkText, width: 1.1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _canSave;
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
            onPressed: () async {
              final shouldPop = await _handleBackPress();
              if (shouldPop) {
                _allowProgrammaticPop = true;
                if (mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
          title: const Text(
            'Upload Document',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: Stack(
          children: [
            SafeArea(
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
                              Text('Document name', style: _labelStyle),
                              const SizedBox(height: UiTokens.s6),
                              TextFormField(
                                controller: _nameCtrl,
                                style: _inputFieldTextStyle,
                                decoration: _defaultDecoration(
                                  hintText: 'e.g. Police clearance',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Provide a document name.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: UiTokens.s12),
                              const Text('Upload file', style: _labelStyle),
                              const SizedBox(height: UiTokens.s6),
                              TextFormField(
                                controller: _fileNameCtrl,
                                onTap: _pickFile,
                                style: _inputFieldTextStyle,
                                decoration:
                                    _defaultDecoration(
                                      hintText: 'Select a file',
                                    ).copyWith(
                                      suffixIcon: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.upload_file,
                                            size: 18,
                                          ),
                                          color: _profileDarkText,
                                          onPressed: _pickFile,
                                        ),
                                      ),
                                    ),
                                validator: (value) {
                                  if ((value == null || value.trim().isEmpty) &&
                                      _existingFileUrl == null &&
                                      _selectedFile == null) {
                                    return 'Select a file.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: UiTokens.s4),
                              const Text(
                                'Size enforced by upload service.',
                                style: _inputFieldHintStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: UiTokens.s6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canSubmit ? _saveDocument : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmit
                                ? _accentGold
                                : Colors.grey[300],
                            foregroundColor: canSubmit
                                ? Colors.black
                                : Colors.white70,
                            padding: const EdgeInsets.symmetric(
                              vertical: UiTokens.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            elevation: canSubmit ? 2 : 0,
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isSaving)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.white.withOpacity(0.7),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
