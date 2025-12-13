import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import 'profile_address_edit_screen.dart';
import 'profile_overview_screen.dart';

const Color _profileDarkText = Color(0xFF1B1D29);

class ProfileAddressesScreen extends StatelessWidget {
  const ProfileAddressesScreen({super.key});

  IconData _getIcon(String label) {
    switch (label) {
      case "Home":
        return Icons.home_rounded;
      case "Office":
        return Icons.apartment_rounded;
      case "Parents":
        return Icons.group_rounded;
      case "Kampung":
        return Icons.park_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Future<void> _setAsDefault(String userId, String addressId) async {
    final userRef = FirebaseFirestore.instance.collection("users").doc(userId);
    final doc = await userRef.get();
    if (!doc.exists) return;
    final list = _extractAddressListFromDocument(doc.data());
    var changed = false;
    for (final entry in list) {
      final id = entry["id"]?.toString();
      if (id == addressId) {
        if (entry["isDefault"] != true) {
          entry["isDefault"] = true;
          changed = true;
        }
      } else if (entry["isDefault"] == true) {
        entry["isDefault"] = false;
        changed = true;
      }
    }
    if (changed) {
      await userRef.update({"address": list});
    }
  }

  Future<void> _deleteAddress(String userId, String addressId) async {
    final userRef = FirebaseFirestore.instance.collection("users").doc(userId);
    final doc = await userRef.get();
    if (!doc.exists) return;
    final list = _extractAddressListFromDocument(doc.data());
    final filtered = list.where((entry) {
      final id = entry["id"]?.toString();
      return id != addressId;
    }).toList();
    if (filtered.length != list.length) {
      await userRef.update({"address": filtered});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please sign in to view addresses.")),
      );
    }

    final userDocRef = FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid);

    final stream = userDocRef.snapshots();

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
          onPressed: () => _returnToOverview(context),
        ),
        title: const Text(
          "Family Addresses",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: _profileDarkText,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                "Failed to load addresses: ${snap.error}",
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snap.data!;
          final addresses = _extractAddressListFromDocument(doc.data());
          final sortedDocs = addresses
            ..sort((a, b) {
              final ad = (a["isDefault"] ?? false) ? 1 : 0;
              final bd = (b["isDefault"] ?? false) ? 1 : 0;
              if (ad != bd) return bd - ad;
              return 0;
            });

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 2),
                _DashedAddCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileAddressEditScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (sortedDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.location_off,
                          color: Colors.black26,
                          size: 32,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "You haven't added any addresses yet.",
                          style: TextStyle(color: Colors.black45, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ...sortedDocs.map((entry) {
                  final id = entry["id"]?.toString();
                  final label = entry["label"] ?? "";
                  final isDefault = entry["isDefault"] ?? false;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AddressCard(
                      id: id ?? "",
                      name: entry["name"] ?? "",
                      phone: entry["phone"] ?? "",
                      address: entry["address"] ?? "",
                      label: label,
                      isDefault: isDefault,
                      onEdit: () {
                        if (id?.isEmpty ?? true) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfileAddressEditScreen(addressId: id),
                          ),
                        );
                      },
                      onSetDefault: isDefault || id == null || id.isEmpty
                          ? null
                          : () => _setAsDefault(user.uid, id),
                      onDelete: id == null || id.isEmpty
                          ? () {}
                          : () => _deleteAddress(user.uid, id),
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

  List<Map<String, dynamic>> _extractAddressListFromDocument(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return [];
    final raw = data["address"];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  void _returnToOverview(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProfileOverviewScreen()),
      );
    }
  }
}

class _DashedAddCard extends StatelessWidget {
  final VoidCallback onTap;

  const _DashedAddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add, color: Colors.black54, size: 18),
            SizedBox(width: 8),
            Text(
              "Add New Address",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String label;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback? onSetDefault;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.label,
    required this.isDefault,
    required this.onEdit,
    required this.onSetDefault,
    required this.onDelete,
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
            spreadRadius: 0.5,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                DefaultProfileAvatar(
                  radius: 16,
                  label: name,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Default',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (label.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
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
                  height: 1.5,
                  color: Colors.black.withAlpha(20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: "Edit",
                    icon: Icons.edit_outlined,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: isDefault ? "Default" : "Set Default",
                    icon: isDefault ? Icons.check : Icons.star_outline,
                    isPrimary: !isDefault,
                    onTap: onSetDefault,
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
        ? (isEnabled ? const Color(0xFF00A8A7) : Colors.grey[400])
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
          borderRadius: BorderRadius.circular(12),
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
