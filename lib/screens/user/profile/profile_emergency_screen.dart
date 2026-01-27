import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import 'profile_emergency_edit_screen.dart';

const Color _tealAccent = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _reminderIconColor = Color(0xFF00A8A7);
const TextStyle _emergencyNameStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: Colors.black87,
);
final TextStyle _emergencyRelationshipStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w500,
  color: Colors.grey[500],
);
final TextStyle _emergencyPhoneStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: Colors.grey[700],
  height: 1.2,
);

class ProfileEmergencyScreen extends StatelessWidget {
  const ProfileEmergencyScreen({super.key});

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
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

  Future<void> _deleteContact(String userId, String contactId) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final doc = await userRef.get();
    if (!doc.exists) return;
    final contacts = _extractEmergencyList(doc.data());
    final filtered = contacts
        .where((entry) => entry['id'] != contactId)
        .toList();
    if (filtered.length == contacts.length) return;
    await userRef.update({'emergencyContacts': filtered});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view emergency contacts.')),
      );
    }

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
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _profileDarkText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Emergency Contacts',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: _profileDarkText,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDocStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load emergency contacts: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final contacts = _extractEmergencyList(snapshot.data!.data());
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                _DashedAddCard(
                  label: "Add Emergency Contact",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileEmergencyEditScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (contacts.isEmpty)
                  _buildEmptyReminder(
                    icon: Icons.call,
                    headline: 'No emergency contacts',
                    explanation:
                        'Add someone we can reach in case you need urgent support.',
                  ),
                ...contacts.map((entry) {
                  final id = entry['id']?.toString() ?? '';
                  final name = entry['name']?.toString() ?? '';
                  final phone = entry['phone']?.toString() ?? '';
                  final relationship = entry['relationship']?.toString() ?? '';
                  final hasId = id.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EmergencyContactCard(
                      name: name,
                      phone: phone,
                      relationship: relationship,
                      photoUrl: entry['photoUrl']?.toString(),
                      onCall: phone.isNotEmpty
                          ? () => _dialNumber(context, phone)
                          : null,
                      onEdit: hasId
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProfileEmergencyEditScreen(contactId: id),
                                ),
                              );
                            }
                          : null,
                      onDelete: hasId
                          ? () => _deleteContact(user.uid, id)
                          : null,
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _dialNumber(BuildContext context, String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    final telUri = Uri(scheme: 'tel', path: trimmed);
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      } else {
        _showSnack(context, 'Unable to place the call.');
      }
    } catch (_) {
      _showSnack(context, 'Unable to place the call.');
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DashedAddCard extends StatelessWidget {
  final VoidCallback onTap;

  final String label;
  const _DashedAddCard({
    required this.onTap,
    this.label = "Add New Emergency Contact",
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _accentGold,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _accentGold.withValues(alpha: 0.55),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
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

class _EmergencyContactCard extends StatelessWidget {
  final String name;
  final String phone;
  final String relationship;
  final String? photoUrl;
  final VoidCallback? onCall;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EmergencyContactCard({
    required this.name,
    required this.phone,
    required this.relationship,
    this.photoUrl,
    this.onCall,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 6),
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                DefaultProfileAvatar(
                  radius: 26,
                  photoUrl: photoUrl,
                  label: name,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: _emergencyNameStyle,
                      ),
                      if (relationship.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          relationship,
                          style: _emergencyRelationshipStyle,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: _emergencyPhoneStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Call',
                    icon: Icons.call,
                    isPrimary: true,
                    onTap: onCall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
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
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    final background = isPrimary
        ? (isEnabled ? _tealAccent : Colors.grey[400])
        : Colors.white;
    final foreground = isPrimary
        ? Colors.white
        : Colors.black87.withValues(alpha: isEnabled ? 1 : 0.35);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(isPrimary ? 12 : 12),
          border: Border.all(
            color: isPrimary
                ? Colors.transparent
                : Colors.grey.withValues(alpha: isEnabled ? 0.35 : 0.2),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildEmptyReminder({
  required IconData icon,
  required String headline,
  required String explanation,
  Color iconColor = _reminderIconColor,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 32, color: iconColor),
        const SizedBox(height: 10),
        Text(
          headline,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: _profileDarkText,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          explanation,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
