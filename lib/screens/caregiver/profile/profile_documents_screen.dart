import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui_tokens.dart';
import '../../user/profile/profile_overview_screen.dart';
import 'profile_documents_edit_screen.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);

const TextStyle _appBarTitleStyle = TextStyle(
  color: _profileDarkText,
  fontSize: 18,
  fontWeight: FontWeight.w600,
);
const TextStyle _documentTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
const TextStyle _documentFileStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: _profileDarkText60,
);
const TextStyle _documentMetaStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: _profileDarkText60,
);
const Color _primaryBlue = Color(0xFF00A8A7);

const TextStyle _statusChipTextStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  color: Colors.black87,
);
const TextStyle _actionLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);

const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];

final DateFormat _docDateFormat = DateFormat('MMM d, yyyy');

class ProfileDocumentsScreen extends StatefulWidget {
  const ProfileDocumentsScreen({super.key});

  @override
  State<ProfileDocumentsScreen> createState() => _ProfileDocumentsScreenState();
}

class _ProfileDocumentsScreenState extends State<ProfileDocumentsScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _documentsStream;
  static const double _emptyStateHeight = 232;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _documentsStream = FirebaseFirestore.instance
          .collection('documents')
          .where('caregiverId', isEqualTo: user.uid)
          .snapshots();
    }
  }

  void _navigateToEdit({String? documentId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDocumentsEditScreen(documentId: documentId),
      ),
    );
  }

  void _returnToOverview() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProfileOverviewScreen()),
      );
    }
  }

  Future<void> _deleteDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete document?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
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
                backgroundColor: _tealAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Delete'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final url = document.data()?['storagePath'] as String?;
    if (url != null && url.isNotEmpty) {
      await FirebaseStorage.instance.ref(url).delete().catchError((_) {});
    }
    await document.reference.delete();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _removeFromCaregiverDocuments(user.uid, document.id);
    }
    _showSnack('Document removed.');
  }

  Future<void> _removeFromCaregiverDocuments(
    String caregiverId,
    String docId,
  ) async {
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId);
    final snapshot = await caregiverRef.get();
    final raw = snapshot.data()?['documents'];
    final entries = <Map<String, dynamic>>[];
    if (raw is Iterable) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          entries.add(Map<String, dynamic>.from(item));
        } else if (item is Map) {
          entries.add(Map<String, dynamic>.from(item.cast()));
        }
      }
    }
    final filtered = entries.where((entry) => entry['id'] != docId).toList();
    await caregiverRef.set({'documents': filtered}, SetOptions(merge: true));
  }

  Future<void> _handleDocumentAction(String? link, String fallback) async {
    if (link == null || link.isEmpty) {
      _showSnack(fallback);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showSnack('Unable to open the document.');
      return;
    }
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      _showSnack('Unable to open the document.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildDocumentList(
    List<DocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final sorted = [...documents];
    sorted.sort((a, b) {
      final aDate = (a.data()?['updatedAt'] as Timestamp?)?.toDate();
      final bDate = (b.data()?['updatedAt'] as Timestamp?)?.toDate();
      final aValue = aDate?.millisecondsSinceEpoch ?? 0;
      final bValue = bDate?.millisecondsSinceEpoch ?? 0;
      return bValue.compareTo(aValue);
    });
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 2),
          _AddDocumentCard(onTap: () => _navigateToEdit()),
          const SizedBox(height: 12),
          if (sorted.isEmpty) ...[
            _buildDocumentsEmptyState(),
          ],
          for (final doc in sorted) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DocumentCard(
                document: doc,
                onView: () => _handleDocumentAction(
                  doc.data()?['fileUrl'] as String?,
                  'No file available to view.',
                ),
                onEdit: () => _navigateToEdit(documentId: doc.id),
                onDelete: () => _deleteDocument(doc),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenteredEmptyMessage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return SizedBox(
      height: _emptyStateHeight,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 32, color: _tealAccent),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _profileDarkText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentsEmptyState() {
    return _buildCenteredEmptyMessage(
      icon: Icons.description_outlined,
      title: 'No documents yet',
      subtitle: 'Upload ID cards or certifications to share your qualifications.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: _buildCenteredEmptyMessage(
          icon: Icons.description_outlined,
          title: 'Please sign in',
          subtitle: 'Sign in to upload and manage your documents.',
        ),
      );
    }
    final stream =
        _documentsStream ??
        FirebaseFirestore.instance
            .collection('documents')
            .where('caregiverId', isEqualTo: user.uid)
            .snapshots();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildCenteredEmptyMessage(
              icon: Icons.description_outlined,
              title: 'Unable to load documents',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildDocumentList(snapshot.data!.docs);
        },
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
        onPressed: _returnToOverview,
      ),
      title: const Text('Documents', style: _appBarTitleStyle),
    );
  }
}

class _AddDocumentCard extends StatelessWidget {
  const _AddDocumentCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(UiTokens.r16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _accentGold,
          borderRadius: BorderRadius.circular(UiTokens.r16),
          border: Border.all(color: _accentGold.withValues(alpha: 0.55), width: 1.1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add, color: Colors.black, size: 18),
            SizedBox(width: 8),
            Text(
              "Add New Document",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final DocumentSnapshot<Map<String, dynamic>> document;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final data = document.data() ?? {};
    final uploadedAt = (data['updatedAt'] as Timestamp?)?.toDate();
    final dateLabel = uploadedAt != null
        ? 'Uploaded: ${_docDateFormat.format(uploadedAt)}'
        : 'Uploaded: unknown';
    final docName = (data['name'] as String?) ?? 'Document';
    final fileLabel = (data['fileName'] as String?) ?? 'PDF File';
    final isVerified = data['status'] as bool? ?? false;
    final borderColor = Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: _cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _primaryBlue.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: UiTokens.icon24,
                  color: _tealAccent,
                ),
              ),
              const SizedBox(width: UiTokens.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(docName, style: _documentTitleStyle),
                        ),
                        _StatusChip(verified: isVerified),
                      ],
                    ),
                    const SizedBox(height: UiTokens.s4),
                    Text(fileLabel, style: _documentFileStyle),
                    const SizedBox(height: UiTokens.s2),
                    Text(dateLabel, style: _documentMetaStyle),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: Container(
                  height: 1.2,
                  color: Colors.black.withAlpha(20),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _DocumentActionButton(
                  icon: Icons.remove_red_eye,
                  label: 'View',
                  onTap: onView,
                  primary: true,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _DocumentActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outlined,
                    size: UiTokens.icon20,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentActionButton extends StatelessWidget {
  const _DocumentActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = primary ? _tealAccent : Colors.white;
    final borderColor = primary ? _tealAccent : Colors.grey.shade300;
    final foreground = primary ? Colors.white : _profileDarkText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(label, style: _actionLabelStyle.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final dotColor = verified ? Colors.green.shade700 : Colors.grey.shade600;
    final borderColor = Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UiTokens.s8,
        vertical: UiTokens.s4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'Verified' : 'Unverified',
            style: _statusChipTextStyle,
          ),
        ],
      ),
    );
  }
}
