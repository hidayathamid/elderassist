import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import 'profile_address_edit_screen.dart';
import 'profile_overview_screen.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _tealAccent = Color(0xFF00B8C6);
const Color _reminderIconColor = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);

class ProfileAddressesScreen extends StatefulWidget {
  const ProfileAddressesScreen({
    super.key,
    this.selectionMode = false,
    this.selectionModeForBookingEdit = false,
  });

  final bool selectionMode;
  final bool selectionModeForBookingEdit;

  @override
  State<ProfileAddressesScreen> createState() => _ProfileAddressesScreenState();
}

class _ProfileAddressesScreenState extends State<ProfileAddressesScreen> {
  String? _selectedAddressId;
  Map<String, dynamic>? _selectedAddress;

  bool get _isSelectionMode => widget.selectionMode;
  bool get _isBookingEditSelectionMode =>
      widget.selectionMode && widget.selectionModeForBookingEdit;
  bool get _showAddCard =>
      !_isSelectionMode || widget.selectionModeForBookingEdit == false;
  bool get _showActionButtons =>
      !_isSelectionMode || widget.selectionModeForBookingEdit == false;
  bool _autoDefaulting = false;

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

  void _autoDefaultSingleAddress(String userId, String addressId) {
    if (_autoDefaulting) return;
    _autoDefaulting = true;
    _setAsDefault(userId, addressId).whenComplete(() {
      _autoDefaulting = false;
    });
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
          if (sortedDocs.length == 1) {
            final onlyEntry = sortedDocs.first;
            final id = onlyEntry["id"]?.toString();
            final isDefault = onlyEntry["isDefault"] ?? false;
            if (id != null && !isDefault) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _autoDefaultSingleAddress(user.uid, id);
              });
            }
          }

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showAddCard) ...[
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
                ],
                if (sortedDocs.isEmpty)
                  _buildEmptyReminder(
                    icon: Icons.location_off,
                    headline: 'No addresses yet',
                    explanation:
                        'Add your family members so we can book caregivers for them.',
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
                      photoUrl: entry["photoUrl"]?.toString(),
                      label: label,
                      isDefault: isDefault,
                      isSelected: _isSelectionMode && id == _selectedAddressId,
                      selectionMode: _isSelectionMode,
                      compact: _isBookingEditSelectionMode,
                      showActions: _showActionButtons,
                      onSelect: _isSelectionMode
                          ? () {
                              setState(() {
                                _selectedAddressId = id;
                                _selectedAddress =
                                    Map<String, dynamic>.from(entry);
                              });
                            }
                          : null,
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
      bottomNavigationBar: _isSelectionMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ElevatedButton(
                  onPressed: _selectedAddress == null
                      ? null
                      : () => Navigator.of(context).pop(_selectedAddress),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Choose this person'),
                ),
              ),
            )
          : null,
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
  final String? photoUrl;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback? onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback? onSelect;
  final bool isSelected;
  final bool selectionMode;
  final bool compact;
  final bool showActions;

  const _AddressCard({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.label,
    this.photoUrl,
    required this.isDefault,
    required this.onEdit,
    required this.onSetDefault,
    required this.onDelete,
    this.onSelect,
    this.isSelected = false,
    this.selectionMode = false,
    this.compact = false,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? _tealAccent : Colors.grey.shade300;
    final double borderWidth = isSelected ? 1.6 : 1.0;
    final cardColor = isSelected ? const Color(0xFFE4F4FF) : Colors.white;
    final horizontalPadding = compact ? 10.0 : 12.0;
    final verticalPadding = compact ? 6.0 : 8.0;
    final dividerPadding = compact ? 4.0 : 6.0;

    final cardContent = Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
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
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DefaultProfileAvatar(
                  radius: compact ? 24 : 26,
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (label.isNotEmpty) ...[
                        SizedBox(height: compact ? 2 : 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                      if (phone.isNotEmpty) ...[
                        SizedBox(height: compact ? 2 : 4),
                        Text(
                          phone,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                            height: 1.2,
                          ),
                        ),
                      ],
                      if (address.isNotEmpty) ...[
                        SizedBox(height: compact ? 2 : 4),
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
                    ],
                  ),
                ),
                if (selectionMode)
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Center(
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.black26,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: dividerPadding),
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
          if (showActions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: isDefault ? "Default" : "Set Default",
                      icon: isDefault ? Icons.check : Icons.star_outline,
                      isPrimary: !isDefault,
                      onTap: onSetDefault,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: "Edit",
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

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: cardContent,
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
