import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/auth_wrapper.dart';
import '../../widgets/default_profile_avatar.dart';
import 'admin_caregiver_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_ui.dart';
import 'admin_reviews_screen.dart';
import 'admin_verifications_screen.dart';
import '../user/profile/profile_edit_screen.dart';

const Color _accentGold = adminAccentGold;
const Color _tealAccent = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileBackground = Color(0xFFF6F7F9);
const Color _serviceChipBorder = Color(0xFFCCCCCC);
const Color _profileCardBorder = Color(0xFFD7DCE3);
const double _pageHorizontalPadding = 14.0;
const double _cardRadius = 18.0;

const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _profileDarkText,
);
const TextStyle _profileDialogTitleStyle = TextStyle(
  fontWeight: FontWeight.w700,
);
const TextStyle _profileDialogContentStyle = TextStyle(color: Colors.black87);

class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 4,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: tabIndex,
      child: _AdminProfileOverview(tabIndexListenable: tabIndexListenable),
    );
  }
}

class _AdminProfileOverview extends StatelessWidget {
  const _AdminProfileOverview({this.tabIndexListenable});

  final ValueListenable<int>? tabIndexListenable;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: _profileBackground,
        appBar: _buildAppBar(),
        body: const Center(child: Text('Please sign in to view your profile')),
      );
    }

    final uid = user.uid.trim();
    if (uid.isEmpty) {
      return Scaffold(
        backgroundColor: _profileBackground,
        appBar: _buildAppBar(),
        body: const Center(child: Text('Please sign in to view your profile')),
      );
    }

    final adminDocRef = FirebaseFirestore.instance.collection('admin').doc(uid);
    final adminDocStream = adminDocRef.snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: adminDocStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: _profileBackground,
            appBar: _buildAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final fallbackName = (user.displayName ?? '').trim();
        final fallbackEmail = (user.email ?? '').trim();

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _profileBackground,
            appBar: _buildAppBar(),
            body: _AdminProfileContent(
              tabIndexListenable: tabIndexListenable,
              uid: uid,
              adminDocRef: adminDocRef,
              name: fallbackName.isNotEmpty ? fallbackName : 'Admin',
              email: fallbackEmail.isNotEmpty ? fallbackEmail : uid,
              roleLabel: 'Admin',
              photoUrl: null,
              notice:
                  'Admin document could not be read. Ensure `admin/$uid` exists and Firestore rules allow this user to read it.\n\n${snapshot.error}',
            ),
          );
        }

        final snap = snapshot.data;
        final data = snap?.data() ?? const <String, dynamic>{};
        final name = ((data['name'] as String?) ?? fallbackName).trim();
        final email = ((data['email'] as String?) ?? fallbackEmail).trim();
        final roleLabel = ((data['role'] as String?) ?? 'admin').trim();
        final photoUrl = ((data['photoUrl'] as String?) ?? '').trim();

        final notice = (snap?.exists == true)
            ? null
            : 'Admin document not found. Create a document at `admin/$uid` to enable admin profile fields.';

        return Scaffold(
          backgroundColor: _profileBackground,
          appBar: _buildAppBar(),
          body: _AdminProfileContent(
            tabIndexListenable: tabIndexListenable,
            uid: uid,
            adminDocRef: adminDocRef,
            name: name.isNotEmpty ? name : 'Admin',
            email: email.isNotEmpty ? email : uid,
            roleLabel: roleLabel.isNotEmpty ? roleLabel : 'admin',
            photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
            notice: notice,
          ),
        );
      },
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
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
      title: const Text(
        'Account',
        style: TextStyle(
          color: _profileDarkText,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
    );
  }
}

class _AdminProfileContent extends StatelessWidget {
  const _AdminProfileContent({
    required this.tabIndexListenable,
    required this.uid,
    required this.adminDocRef,
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.photoUrl,
    this.notice,
  });

  final ValueListenable<int>? tabIndexListenable;
  final String uid;
  final DocumentReference<Map<String, dynamic>> adminDocRef;
  final String name;
  final String email;
  final String roleLabel;
  final String? photoUrl;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _pageHorizontalPadding,
              4,
              _pageHorizontalPadding,
              4,
            ),
            child: _buildProfileCard(),
          ),
          if (notice != null && notice!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _pageHorizontalPadding,
              ),
              child: buildAdminEmptyState(
                icon: Icons.info_outline,
                title: 'Admin profile note',
                subtitle: notice!.trim(),
              ),
            ),
          ],
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _pageHorizontalPadding,
              4,
              _pageHorizontalPadding,
              6,
            ),
            child: _buildSectionHeader(
              title: 'Verification activity',
              hint:
                  'A quick overview of pending verifications across the system.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _pageHorizontalPadding,
            ),
            child: _AdminVerificationActivityCard(),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _pageHorizontalPadding,
              4,
              _pageHorizontalPadding,
              6,
            ),
            child: _buildSectionHeader(
              title: 'List of services',
              hint: 'These are the services shown throughout the app.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _pageHorizontalPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _profileCardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                height: 44,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('services')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? const [];
                    final names =
                        docs
                            .map(
                              (d) =>
                                  ((d.data()['name'] as String?) ?? '').trim(),
                            )
                            .where((e) => e.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort();
                    if (names.isEmpty) {
                      return Center(
                        child: Text(
                          'No services yet',
                          style: TextStyle(
                            color: _profileDarkText.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(names.length * 2 - 1, (
                            index,
                          ) {
                            if (index.isEven) {
                              final option = names[index ~/ 2];
                              return _AdminServiceChip(
                                label: option,
                                selected: true,
                              );
                            }
                            return const SizedBox(width: 6);
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _pageHorizontalPadding,
              4,
              _pageHorizontalPadding,
              6,
            ),
            child: _buildSectionHeader(
              title: 'Account & Monitoring',
              hint: 'Manage your profile and jump to admin workflows.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _pageHorizontalPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _ZUSRow(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    count: 0,
                    onTap: () => _openEditProfile(context),
                  ),
                  const _ZUSDivider(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('documents')
                        .where('status', isEqualTo: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final pending = snapshot.data?.size ?? 0;
                      return _ZUSRow(
                        icon: Icons.verified_user_outlined,
                        label: 'Caregiver Verifications',
                        count: pending > 0 ? pending : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminCaregiverScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('withdrawRequests')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final pending = snapshot.data?.size ?? 0;
                      return _ZUSRow(
                        icon: Icons.payments_outlined,
                        label: 'Payment withdraw & refund',
                        count: pending > 0 ? pending : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                             builder: (_) => const AdminVerificationsScreen(
                               initialTabIndex: 0,
                             ),
                           ),
                         ),
                       );
                    },
                  ),
                  const _ZUSDivider(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('services')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.size ?? 0;
                      return _ZUSRow(
                        icon: Icons.medical_services_outlined,
                        label: 'Services Overview',
                        count: count > 0 ? count : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminReviewsScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('documents')
                        .where('status', isEqualTo: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final pending = snapshot.data?.size ?? 0;
                      return _ZUSRow(
                        icon: Icons.description_outlined,
                        label: 'Documents Verifications',
                        count: pending > 0 ? pending : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminDocumentsScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _pageHorizontalPadding,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await _confirmLogout(context);
                  if (!ok) return;
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthWrapper()),
                    (_) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Log out'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _openEditProfile(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileEditScreen(
          useAdminData: true,
          hideAddressField: true,
          hideBioField: true,
          hidePhoneField: true,
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DefaultProfileAvatar(
            radius: 32,
            photoUrl: photoUrl,
            label: name.isNotEmpty ? name : email,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _profileDarkText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Admin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _profileDarkText.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: _profileDarkText.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required String hint}) {
    return Row(
      children: [
        Text(title, style: _sectionTitleStyle),
        const SizedBox(width: 6),
        _ProfileSectionInfoIcon(message: hint),
      ],
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Log out?',
          textAlign: TextAlign.center,
          style: _profileDialogTitleStyle,
        ),
        content: const Text(
          'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: _profileDialogContentStyle,
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
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
              ),
              child: const Text(
                'Log out',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _AdminVerificationActivityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final unverifiedDocsStream = FirebaseFirestore.instance
        .collection('documents')
        .where('status', isEqualTo: false)
        .snapshots();
    final pendingWithdrawStream = FirebaseFirestore.instance
        .collection('withdrawRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: unverifiedDocsStream,
      builder: (context, docsSnapshot) {
        final docs = docsSnapshot.data?.docs ?? const [];
        final caregivers = <String>{};
        for (final doc in docs) {
          final caregiverId =
              (doc.data()['caregiverId'] as String?)?.trim() ?? '';
          if (caregiverId.isNotEmpty) caregivers.add(caregiverId);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: pendingWithdrawStream,
          builder: (context, withdrawSnapshot) {
            final pendingWithdraw = withdrawSnapshot.data?.docs.length ?? 0;
            final caregiverCount = caregivers.length;
            final unverifiedDocs = docs.length;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_cardRadius),
                border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _SummaryItem(
                    title: 'Caregiver',
                    value: caregiverCount,
                    icon: Icons.volunteer_activism_outlined,
                  ),
                  _SummaryItem(
                    title: 'Payment',
                    value: pendingWithdraw,
                    icon: Icons.payments_outlined,
                  ),
                  _SummaryItem(
                    title: 'Document',
                    value: unverifiedDocs,
                    icon: Icons.description_outlined,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const itemColor = _tealAccent;
    return Column(
      children: [
        Icon(icon, size: 16, color: itemColor),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _ZUSDivider extends StatelessWidget {
  const _ZUSDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Colors.black.withValues(alpha: 0.06));
  }
}

class _AdminServiceChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _AdminServiceChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final background = selected ? _accentGold : Colors.white;
    final foreground = selected ? Colors.black : _profileDarkText;
    final borderColor = selected
        ? _accentGold.withValues(alpha: 0.45)
        : _serviceChipBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minHeight: 26),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ZUSRow extends StatelessWidget {
  const _ZUSRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final displayCount = count ?? 0;
    final showCount = displayCount > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _tealAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _profileDarkText,
                ),
              ),
            ),
            if (showCount) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _accentGold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  displayCount.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, color: Color(0xFFC7C7C7), size: 20),
          ],
        ),
      ),
    );
  }
}

class _ProfileSectionInfoIcon extends StatefulWidget {
  const _ProfileSectionInfoIcon({required this.message});

  final String message;

  @override
  State<_ProfileSectionInfoIcon> createState() =>
      _ProfileSectionInfoIconState();
}

class _ProfileSectionInfoIconState extends State<_ProfileSectionInfoIcon> {
  bool _showHint = false;
  Timer? _hintTimer;

  void _triggerHint() {
    _hintTimer?.cancel();
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _triggerHint,
          onLongPress: _triggerHint,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.info_outline, size: 16, color: _tealAccent),
          ),
        ),
        if (_showHint)
          Positioned(
            right: -170,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
