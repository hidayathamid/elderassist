import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_addresses_screen.dart';
import 'profile_edit_screen.dart';
import 'profile_emergency_screen.dart';
import 'profile_payments_screen.dart';
import 'profile_services_screen.dart';

import '../../../models/activity_booking.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../auth/touchdown_screen.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _serviceChipBorder = Color(0xFFCCCCCC);

class ProfileOverviewScreen extends StatelessWidget {
  const ProfileOverviewScreen({super.key});

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _bookingStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<Map<String, dynamic>> _extractAddressList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['address'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _extractEmergencyList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['emergencyContacts'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  List<String> _extractServicePreferences(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['servicePreferences'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return [];
  }

  BookingStatus _profileBookingStatusFromString(String status) {
    switch (status.toUpperCase()) {
      case 'ONGOING':
      case 'IN_PROGRESS':
        return BookingStatus.ongoing;
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'CANCELLED':
      case 'CANCELED':
        return BookingStatus.cancelled;
      case 'ASSIGNED':
      case 'PENDING':
      default:
        return BookingStatus.pending;
    }
  }

  bool _isUpcomingBookingStatus(BookingStatus status) {
    return status == BookingStatus.pending || status == BookingStatus.ongoing;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        title: const Text(
          "Account",
          style: TextStyle(
            color: _profileDarkText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text("Unable to load profile."));
          }
          final doc = snap.data!;
          final data = {...doc.data()!, "uid": doc.id};
          final user = UserModel.fromMap(data);
          final addresses = _extractAddressList(doc.data());
          final emergencyContacts = _extractEmergencyList(doc.data());
          final servicePreferences = _extractServicePreferences(doc.data());
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _bookingStream(),
            builder: (context, bookingSnap) {
              final bookingDocs = bookingSnap.data?.docs ?? const [];
              final upcomingDocs = bookingDocs.where((doc) {
                final rawStatus = (doc.data()['status'] as String?) ?? 'PENDING';
                final status = _profileBookingStatusFromString(rawStatus);
                return _isUpcomingBookingStatus(status);
              }).toList();
              final caregivers = <String>{};
              final families = <String>{};
              for (final doc in upcomingDocs) {
                final data = doc.data();
                final caregiverId =
                    ((data['caregiverId'] as String?) ?? '').trim();
                if (caregiverId.isNotEmpty) caregivers.add(caregiverId);
                final personName =
                    ((data['personName'] as String?) ?? '').trim();
                if (personName.isNotEmpty) families.add(personName);
              }
              return _buildOverviewContent(
                context: context,
                user: user,
                addresses: addresses,
                emergencyContacts: emergencyContacts,
                servicePreferences: servicePreferences,
                bookingsCount: upcomingDocs.length,
                caregiversCount: caregivers.length,
                familyCount: families.length,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOverviewContent({
    required BuildContext context,
    required UserModel user,
    required List<Map<String, dynamic>> addresses,
    required List<Map<String, dynamic>> emergencyContacts,
    required List<String> servicePreferences,
    required int bookingsCount,
    required int caregiversCount,
    required int familyCount,
  }) {
    final addressesCount = addresses.length;
    final emergencyCount = emergencyContacts.length;
    final servicePreferencesCount = servicePreferences.length;
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color.fromARGB(
                      255,
                      181,
                      212,
                      212,
                    ).withValues(alpha: 0.1),
                    backgroundImage:
                        (user.photoUrl?.isNotEmpty == true) ? NetworkImage(user.photoUrl!) : null,
                    child: (user.photoUrl?.isNotEmpty != true)
                        ? Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : user.email[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _tealAccent,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _profileDarkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: _profileDarkText.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        if (user.phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            user.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: _profileDarkText.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              "Your Activity",
              style: TextStyle(
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SummaryItem(
                    title: "Bookings",
                    value: bookingsCount,
                    icon: Icons.event_note_outlined,
                    color: _tealAccent,
                  ),
                  _SummaryItem(
                    title: "Caregivers",
                    value: caregiversCount,
                    icon: Icons.medical_services_outlined,
                    color: _tealAccent,
                  ),
                  _SummaryItem(
                    title: "Family",
                    value: familyCount,
                    icon: Icons.group_outlined,
                    color: _tealAccent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              "Service Preferences",
              style: TextStyle(
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
                child: servicePreferences.isEmpty
                    ? Center(
                        child: Text(
                          "No services selected",
                          style: TextStyle(
                            color: _profileDarkText.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              servicePreferences.length * 2 - 1,
                              (index) {
                                if (index.isEven) {
                                  final option =
                                      servicePreferences[index ~/ 2];
                                  return _OverviewServiceChip(
                                    label: option,
                                    selected: true,
                                  );
                                }
                                return const SizedBox(width: 6);
                              },
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              "Account & Preferences",
              style: TextStyle(
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
                    label: "Edit Profile",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileEditScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.location_on_outlined,
                    label: "Family Addresses",
                    count: addressesCount > 0 ? addressesCount : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileAddressesScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.phone_in_talk_outlined,
                    label: "Emergency Contacts",
                    count: emergencyCount > 0 ? emergencyCount : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileEmergencyScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.medical_services_outlined,
                    label: "Service Preferences",
                    count: servicePreferencesCount > 0
                        ? servicePreferencesCount
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileServicesScreen(),
                        ),
                      );
                    },
                  ),
                  const _ZUSDivider(),
                  _ZUSRow(
                    icon: Icons.credit_card_outlined,
                    label: "Payments & Billing",
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
                  await AuthService().signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TouchdownScreen(),
                    ),
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
}

class _SummaryItem extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;

  const _SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    this.color = _tealAccent,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color;

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
  final String label;
  final bool selected;

  const _OverviewServiceChip({required this.label, required this.selected});

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
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;

  const _ZUSRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
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

            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: _tealAccent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            const SizedBox(width: 6),

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
