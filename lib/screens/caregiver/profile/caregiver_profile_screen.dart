import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../auth/touchdown_screen.dart';
import '../../../widgets/default_profile_avatar.dart';
import '../../user/profile/profile_edit_screen.dart';
import '../../user/profile/profile_services_screen.dart';
import '../../user/profile/profile_payments_screen.dart';
import 'profile_availability_schedule_screen.dart';
import 'profile_documents_screen.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _serviceChipBorder = Color(0xFFCCCCCC);
const TextStyle _profileDialogTitleStyle = TextStyle(
  fontWeight: FontWeight.w700,
);
const TextStyle _profileDialogContentStyle = TextStyle(color: Colors.black87);

class CaregiverProfileScreen extends StatelessWidget {
  const CaregiverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const Center(child: Text('Please sign in to view your profile')),
      );
    }

    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: _buildAppBar(),
            body: Center(
              child: Text('Failed to load profile: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData ||
            !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: _buildAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data()!;
        final name =
            (data['name'] as String?) ?? user.displayName ?? 'Caregiver';
        final email = (data['email'] as String?) ?? user.email ?? '';
        final phone = (data['phone'] as String?) ?? '';
        final photoUrl = (data['photoUrl'] as String?) ?? '';
        final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final available = (data['availability'] as bool?) ?? true;
        final totalJobs = (data['jobsCompleted'] as num?)?.toInt() ?? 0;
        final monthlyJobs = (data['monthlyJobs'] as num?)?.toInt() ?? 0;
        final services = _stringListFromField(data['services']);
        final documentsCount = (data['documents'] as Iterable?)?.length ?? 0;
        final certificationsCount = data['certifications'] != null ? 1 : 0;
        final availabilitySchedule = data['availabilitySchedule'] as Iterable?;
        final availabilityCount =
            availabilitySchedule?.length ?? (available ? 1 : 0);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: _buildAppBar(),
          body: _buildProfileContent(
            context: context,
            name: name,
            email: email,
            phone: phone,
            photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
            rating: rating,
            available: available,
            jobsCompleted: totalJobs,
            monthlyJobs: monthlyJobs,
            services: services,
            documentsCount: documentsCount,
            certificationsCount: certificationsCount,
            availabilityCount: availabilityCount,
            servicesCount: services.length,
            caregiverRef: caregiverRef,
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
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      title: const Text(
        'Account',
        style: TextStyle(
          color: _profileDarkText,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildProfileContent({
    required BuildContext context,
    required String name,
    required String email,
    required String phone,
    String? photoUrl,
    double? rating,
    required bool available,
    required int jobsCompleted,
    required int monthlyJobs,
    required List<String> services,
    required int documentsCount,
    required int certificationsCount,
    required int availabilityCount,
    required int servicesCount,
    required DocumentReference<Map<String, dynamic>> caregiverRef,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultProfileAvatar(
                    radius: 32,
                    photoUrl: photoUrl,
                    label: name.isNotEmpty ? name : email,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _profileDarkText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 12,
                                  color: available
                                      ? _tealAccent
                                      : Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  rating != null
                                      ? rating.toStringAsFixed(1)
                                      : '-',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    color: available
                                        ? _profileDarkText
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
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
                        if (phone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _profileDarkText.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _buildSectionHeader(
              'Your Activity',
              'Quick look at your jobs and monthly workload.',
              const TextStyle(
                color: _profileDarkText,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _SummaryItem(
                    title: 'Certification',
                    value: certificationsCount,
                    icon: Icons.badge_outlined,
                  ),
                  _SummaryItem(
                    title: 'Jobs',
                    value: jobsCompleted,
                    icon: Icons.event_note_outlined,
                  ),
                  _SummaryItem(
                    title: 'This Month',
                    value: monthlyJobs,
                    icon: Icons.calendar_month_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _buildSectionHeader(
              'Services Offered',
              'The care types that you are currently sharing with families.',
              const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: _profileDarkText,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.black12.withValues(alpha: 0.05),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                height: 44,
                child: services.isEmpty
                    ? Center(
                        child: Text(
                          'No services listed',
                          style: TextStyle(
                            color: _profileDarkText.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(services.length * 2 - 1, (
                              index,
                            ) {
                              if (index.isEven) {
                                final option = services[index ~/ 2];
                                return _OverviewServiceChip(
                                  label: option,
                                  selected: true,
                                );
                              }
                              return const SizedBox(width: 6);
                            }),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _buildSectionHeader(
              'Account & Preferences',
              'Manage your profile, availability, documents, and payout options.',
              const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: _profileDarkText,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _ZUSRow(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ProfileEditScreen(useCaregiverData: true),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.schedule,
                    label: 'Availability Schedule',
                    count: availabilityCount,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ProfileAvailabilityScheduleScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.document_scanner_outlined,
                    label: 'Documents',
                    count: documentsCount,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileDocumentsScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.medical_services_outlined,
                    label: 'Services Offered',
                    count: servicesCount,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileServicesScreen(
                            useServiceOfferedTitle: true,
                          ),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.payment,
                    label: 'Payment Methods',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfilePaymentsScreen(),
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final shouldLogout = await _confirmLogout(context);
                  if (!shouldLogout) return;
                  await AuthService().signOut();
                  await caregiverRef.set({
                    'availability': false,
                  }, SetOptions(merge: true));
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const TouchdownScreen()),
                    (_) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
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

  Widget _buildSectionHeader(String title, String hint, TextStyle style) {
    return Row(
      children: [
        Text(title, style: style),
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
                style: TextStyle(fontWeight: FontWeight.w700),
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
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Log out'),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static List<String> _stringListFromField(Object? value) {
    if (value is Iterable) {
      return value
          .map((e) => e?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .toList();
    }
    return [];
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: itemColor,
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

class _OverviewServiceChip extends StatelessWidget {
  const _OverviewServiceChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final background = selected ? _tealAccent : Colors.white;
    final foreground = selected ? Colors.white : _profileDarkText;
    final borderColor = selected
        ? _tealAccent.withValues(alpha: 0.45)
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
                  color: _tealAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  displayCount.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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

class _ZUSDivider extends StatelessWidget {
  const _ZUSDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFEDEDED));
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
          child: Icon(Icons.info_outline, size: 16, color: _tealAccent),
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
