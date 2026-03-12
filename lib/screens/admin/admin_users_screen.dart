import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'dart:io' show File, Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_tokens.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/safe_network_image.dart';
import '../../widgets/standard_app_bar.dart';
import '../../utils/service_preferences.dart';
import 'admin_ui.dart';
import '../user/activity/activity_screen.dart'
    show
        activityBackgroundColor,
        activityButtonYellow,
        activityPrimaryTextColor;

const Color _primaryBlue = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);

const double _heroHeight = 220.0;
const double _headerCardOverlap = 96.0;
const double _panelMaxExtent = 0.96;

const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];

final DateFormat _userDateFormat = DateFormat('MMM d, yyyy');
final DateFormat _verificationDocumentsDateFormat = DateFormat(
  'MMM d, yyyy • h:mm a',
);

const TextStyle _userTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);

Widget _buildEmptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: _primaryBlue),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: activityPrimaryTextColor,
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
  );
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 3,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: tabIndex,
      child: const _AdminUsersDashboard(),
    );
  }
}

class _ScheduleTimeRange {
  const _ScheduleTimeRange({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class _UsersFilterBar extends StatelessWidget {
  const _UsersFilterBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = switch (selectedIndex) {
      1 => 'Client users',
      2 => 'Caregiver users',
      _ => 'All users',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 30,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: selectedIndex == 0,
                    onTap: () => onSelected(0),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Clients',
                    selected: selectedIndex == 1,
                    onTap: () => onSelected(1),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Caregivers',
                    selected: selectedIndex == 2,
                    onTap: () => onSelected(2),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: _profileDarkText,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? _primaryBlue : Colors.white;
    final foreground = selected ? Colors.white : _profileDarkText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _UsersSearchField extends StatelessWidget {
  const _UsersSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _profileDarkText,
      ),
      decoration: InputDecoration(
        hintText: 'Search user',
        hintStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.35),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: Colors.black.withValues(alpha: 0.50),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

class _UsersListBody extends StatelessWidget {
  const _UsersListBody({
    required this.tabIndex,
    required this.searchClients,
    required this.searchCaregivers,
    required this.searchAll,
    required this.usersSnapshot,
    required this.caregiversSnapshot,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final int tabIndex;
  final String searchClients;
  final String searchCaregivers;
  final String searchAll;
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> usersSnapshot;
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> caregiversSnapshot;
  final ValueChanged<_AdminUserEntry> onView;
  final ValueChanged<_AdminUserEntry> onEdit;
  final ValueChanged<_AdminUserEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (usersSnapshot.hasError || caregiversSnapshot.hasError) {
      return SizedBox(
        height: 320,
        child: _buildEmptyState(
          Icons.group_outlined,
          'Unable to load users',
          'Please try again.',
        ),
      );
    }
    if (!usersSnapshot.hasData || !caregiversSnapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final usersDocs = usersSnapshot.data!.docs;
    final caregiversDocs = caregiversSnapshot.data!.docs;

    final entries = <_AdminUserEntry>[];
    // 0 = All, 1 = Clients, 2 = Caregivers
    if (tabIndex == 0 || tabIndex == 1) {
      for (final doc in usersDocs) {
        entries.add(_AdminUserEntry.fromDoc(doc, type: _AdminUserType.client));
      }
    }
    if (tabIndex == 0 || tabIndex == 2) {
      for (final doc in caregiversDocs) {
        entries.add(
          _AdminUserEntry.fromDoc(doc, type: _AdminUserType.caregiver),
        );
      }
    }

    final search = switch (tabIndex) {
      0 => searchAll,
      1 => searchClients,
      _ => searchCaregivers,
    }.trim().toLowerCase();

    final filtered =
        entries.where((e) {
          if (search.isEmpty) return true;
          return e.name.toLowerCase().contains(search);
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    if (filtered.isEmpty) {
      return SizedBox(
        height: 320,
        child: _buildEmptyState(
          Icons.group_outlined,
          'No results',
          'Try a different name.',
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = filtered[index];
        return _AdminUserCard(
          entry: entry,
          indexNumber: index + 1,
          onView: () => onView(entry),
          onEdit: () => onEdit(entry),
          onDelete: () => onDelete(entry),
        );
      },
    );
  }
}

enum _AdminUserType { client, caregiver }

class _AdminUserEntry {
  const _AdminUserEntry({
    required this.type,
    required this.id,
    required this.ref,
    required this.name,
    required this.email,
    required this.phone,
    required this.photoUrl,
    required this.defaultAddress,
    required this.createdAt,
    this.rating,
    this.availability,
    this.services = const <String>[],
    this.specialization,
  });

  final _AdminUserType type;
  final String id;
  final DocumentReference<Map<String, dynamic>> ref;
  final String name;
  final String email;
  final String phone;
  final String? photoUrl;
  final String defaultAddress;
  final DateTime? createdAt;
  final double? rating;
  final bool? availability;
  final List<String> services;
  final String? specialization;

  static String? _stringValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const <String>[];
  }

  static _AdminUserEntry fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required _AdminUserType type,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = ((data['name'] as String?) ?? '').trim();
    final email = ((data['email'] as String?) ?? '').trim();
    final phone = ((data['phone'] as String?) ?? '').trim();
    final photoUrl =
        _stringValue(data['photoUrl']) ??
        _stringValue(data['avatarUrl']) ??
        _stringValue(data['imageUrl']) ??
        _stringValue(data['image']) ??
        _stringValue(data['profilePhoto']) ??
        _stringValue(data['profile_photo']) ??
        _stringValue(data['profilePhotoUrl']) ??
        _stringValue(data['profile_photo_url']);
    final rating = (data['rating'] as num?)?.toDouble();
    final availability = type == _AdminUserType.caregiver
        ? (data['availability'] as bool?)
        : null;
    final services = type == _AdminUserType.caregiver
        ? _stringList(data['servicePreferences'] ?? data['services'])
        : _stringList(data['servicePreferences']);
    final defaultAddress = _stringValue(data['defaultAddress']) ?? '';
    final createdAt =
        (data['created_at'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();
    final specialization = type == _AdminUserType.caregiver
        ? ((data['specialization'] as String?) ??
                  (data['service'] as String?) ??
                  '')
              .trim()
        : '';
    return _AdminUserEntry(
      type: type,
      id: doc.id,
      ref: doc.reference,
      name: name.isNotEmpty ? name : doc.id,
      email: email,
      phone: phone,
      photoUrl: (photoUrl?.isNotEmpty == true) ? photoUrl : null,
      defaultAddress: defaultAddress,
      createdAt: createdAt,
      rating: rating,
      availability: availability,
      services: services,
      specialization: specialization.isNotEmpty ? specialization : null,
    );
  }
}

class _AdminUserCard extends StatelessWidget {
  const _AdminUserCard({
    required this.entry,
    required this.indexNumber,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final _AdminUserEntry entry;
  final int indexNumber;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.shade300;
    final email = entry.email.trim();
    final phone = entry.phone.trim();
    final address = entry.defaultAddress.trim();
    final label = entry.type == _AdminUserType.caregiver
        ? 'Caregiver'
        : 'Client';
    final createdValue = entry.createdAt != null
        ? _userDateFormat.format(entry.createdAt!)
        : 'Unknown';

    final rows = <({String label, String value})>[
      (label: 'Created', value: createdValue),
      (label: 'User ID', value: entry.id),
      if (email.isNotEmpty) (label: 'Email', value: email),
      if (phone.isNotEmpty) (label: 'Contact', value: phone),
      if (address.isNotEmpty) (label: 'Location', value: address),
    ];

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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  DefaultProfileAvatar(
                    radius: 22,
                    photoUrl: entry.photoUrl?.isNotEmpty == true
                        ? entry.photoUrl
                        : null,
                    label: entry.name.isNotEmpty ? entry.name : '?',
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        indexNumber.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: UiTokens.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            style: _userTitleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _UserTypeChip(label: label),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(
            height: UiTokens.s16,
            thickness: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
          ...List.generate(rows.length, (index) {
            final row = rows[index];
            final isLast = index == rows.length - 1;
            return _UserFieldRow(
              label: row.label,
              value: row.value,
              showBorder: !isLast,
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _UserActionButton(
                  icon: Icons.remove_red_eye,
                  label: 'View',
                  onTap: onView,
                  primary: true,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _UserActionButton(
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

class _UserFieldRow extends StatelessWidget {
  const _UserFieldRow({
    required this.label,
    required this.value,
    this.showBorder = true,
  });

  final String label;
  final String value;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? BorderSide(color: Colors.black.withValues(alpha: 0.06))
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.black.withValues(alpha: 0.50),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value.trim(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _profileDarkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserActionButton extends StatelessWidget {
  const _UserActionButton({
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
    final backgroundColor = primary ? _primaryBlue : Colors.white;
    final borderColor = primary ? _primaryBlue : Colors.grey.shade300;
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

class _UserTypeChip extends StatelessWidget {
  const _UserTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: label == 'Caregiver'
                  ? Colors.green.shade700
                  : adminAccentGold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 7.5,
              color: Colors.black.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyUsersAnalyticsCard extends StatelessWidget {
  const _MonthlyUsersAnalyticsCard({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.clientsCountStream,
    required this.caregiversCountStream,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Stream<int> clientsCountStream;
  final Stream<int> caregiversCountStream;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: StreamBuilder<int>(
        stream: clientsCountStream,
        builder: (context, clientsSnap) {
          return StreamBuilder<int>(
            stream: caregiversCountStream,
            builder: (context, caregiversSnap) {
              final clients = clientsSnap.data ?? 0;
              final caregivers = caregiversSnap.data ?? 0;
              final total = clients + caregivers;

              final segments = <_DonutSegment>[
                _DonutSegment(
                  label: 'Clients',
                  count: clients,
                  color: adminAccentGold,
                ),
                _DonutSegment(
                  label: 'Caregivers',
                  count: caregivers,
                  color: _primaryBlue,
                ),
              ];

              return Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: onPrev,
                        icon: const Icon(Icons.chevron_left),
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Text(
                          monthLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onNext,
                        icon: const Icon(Icons.chevron_right),
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _DonutChart(total: total, segments: segments),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LegendRow(
                                color: Colors.black.withValues(alpha: 0.22),
                                label: 'Total users',
                                value: total,
                              ),
                            ),
                            for (final s in segments) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LegendRow(
                                  color: s.color,
                                  label: s.label,
                                  value: s.count,
                                ),
                              ),
                              if (s.label == 'Caregivers')
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: onGenerateReport,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: adminAccentGold,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text(
                                      'Generate report',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.total, required this.segments});

  final int total;
  final List<_DonutSegment> segments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(140, 140),
            painter: _DonutPainter(total: total, segments: segments),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                total.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: _profileDarkText,
                ),
              ),
              Text(
                'This month',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: _profileDarkText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value.toString(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.total, required this.segments});

  final int total;
  final List<_DonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    stroke.color = Colors.black.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, stroke);

    if (total <= 0) return;
    var startAngle = -math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (final seg in segments) {
      if (seg.count <= 0) continue;
      final sweep = (seg.count / total) * (math.pi * 2);
      stroke.color = seg.color;
      canvas.drawArc(rect, startAngle, sweep, false, stroke);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.segments != segments;
  }
}

Stream<int> _countStream(
  Query<Map<String, dynamic>> query, {
  required Duration refreshEvery,
}) async* {
  Future<int> fetch() async {
    final aggregate = await query.count().get();
    return aggregate.count ?? 0;
  }

  yield await fetch();
  yield* Stream.periodic(refreshEvery).asyncMap((_) => fetch());
}

class _AdminUsersDashboard extends StatefulWidget {
  const _AdminUsersDashboard();

  @override
  State<_AdminUsersDashboard> createState() => _AdminUsersDashboardState();
}

class _AdminUsersDashboardState extends State<_AdminUsersDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  late final TabController _tabController;
  late DateTime _selectedMonth;
  final TextEditingController _searchController = TextEditingController();

  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;
  bool _modalSheetScrimVisible = false;

  bool _syncingSearchText = false;
  String _searchClients = '';
  String _searchCaregivers = '';
  String _searchAll = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _panelController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _tabController.addListener(_handleTabChange);
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _panelController.dispose();
    _panelScrollController.dispose();
    _searchController.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    final target = switch (_tabController.index) {
      0 => _searchAll,
      1 => _searchClients,
      _ => _searchCaregivers,
    };
    if (_searchController.text != target) {
      _syncingSearchText = true;
      _searchController.text = target;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      _syncingSearchText = false;
    }
    if (mounted) setState(() {});
  }

  void _handleSearchChange() {
    if (_syncingSearchText) return;
    final value = _searchController.text.trim();
    setState(() {
      switch (_tabController.index) {
        case 0:
          _searchAll = value;
          break;
        case 1:
          _searchClients = value;
          break;
        default:
          _searchCaregivers = value;
      }
    });
  }

  void _onPanelHandleDragUpdate(double deltaY, double dragRangePx) {
    _panelUserInteracted = true;
    final next = (_panelController.value - (deltaY / dragRangePx)).clamp(
      0.0,
      1.0,
    );
    _panelController.value = next;
  }

  void _onPanelHandleDragEnd(double velocity) {
    _panelUserInteracted = true;
    final v = velocity;
    if (v < -320) {
      _panelController.animateTo(1.0, curve: Curves.easeOutCubic);
      return;
    }
    if (v > 320) {
      _panelController.animateTo(0.0, curve: Curves.easeOutCubic);
      return;
    }
    final snapTarget = _panelController.value >= 0.5 ? 1.0 : 0.0;
    _panelController.animateTo(snapTarget, curve: Curves.easeOutCubic);
  }

  Widget _buildHeroCover() {
    return SizedBox(
      height: _heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/onboarding_emergency.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0, 0.6),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({DateTime start, DateTime end}) _monthRange(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (start: start, end: end);
  }

  String _monthLabel(DateTime month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[(month.month - 1).clamp(0, 11)];
    return '$m ${month.year}';
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUserDetailsSheet(_AdminUserEntry entry) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdminUserDetailsSheet(entry: entry),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _openUserEditSheet(_AdminUserEntry entry) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdminUserEditSheet(entry: entry),
      );
      if (saved == true) _showSnack('Changes saved.');
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _deleteUser(_AdminUserEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: activityBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this user?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This action cannot be undone.',
          textAlign: TextAlign.center,
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
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: activityButtonYellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    BuildContext? loadingDialogContext;
    var loadingOpen = true;

    void closeLoadingIfOpen() {
      if (!loadingOpen) return;
      final ctx = loadingDialogContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      loadingOpen = false;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        loadingDialogContext = dialogContext;
        return const AlertDialog(
          backgroundColor: Colors.white,
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Deleting user…',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    try {
      final callable = _functions.httpsCallable('adminCascadeDeleteUser');
      await callable.call(<String, dynamic>{'uid': entry.id});
      closeLoadingIfOpen();
      if (!mounted) return;
      _showSnack('User deleted.');
    } on FirebaseFunctionsException catch (err) {
      closeLoadingIfOpen();
      if (!mounted) return;
      final message = (err.message ?? '').trim();
      _showSnack(
        message.isNotEmpty
            ? message
            : 'Failed to delete user. Please try again.',
      );
    } catch (_) {
      closeLoadingIfOpen();
      if (!mounted) return;
      _showSnack('Failed to delete user. Please try again.');
    }
  }

  Future<void> _generateMonthlyUsersReport() async {
    final month = _selectedMonth;
    const pdfType = XTypeGroup(label: 'pdf', extensions: ['pdf']);

    BuildContext? loadingDialogContext;
    var loadingOpen = true;

    void closeLoadingIfOpen() {
      if (!loadingOpen) return;
      final ctx = loadingDialogContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      loadingOpen = false;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        loadingDialogContext = dialogContext;
        return const AlertDialog(
          backgroundColor: Colors.white,
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Generating reportâ€¦',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final callable = _functions.httpsCallable(
        'generateAdminUsersReport',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final result = await callable
          .call(<String, dynamic>{'year': month.year, 'month': month.month})
          .timeout(const Duration(seconds: 75));
      final map = Map<String, dynamic>.from(result.data as Map);
      final pdfBase64 = (map['pdfBase64'] as String?) ?? '';
      final fileName =
          (map['fileName'] as String?) ??
          'users-report-${month.year}-${month.month.toString().padLeft(2, '0')}.pdf';
      if (pdfBase64.trim().isEmpty) {
        throw Exception('Missing pdfBase64');
      }
      final bytes = base64Decode(pdfBase64);

      closeLoadingIfOpen();

      if (!kIsWeb &&
          (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia)) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/$fileName';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              'Report ready',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        try {
                          await Share.shareXFiles([
                            XFile(
                              path,
                              mimeType: 'application/pdf',
                              name: fileName,
                            ),
                          ], subject: fileName);
                        } catch (e) {
                          if (!mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              title: const Text(
                                'Unable to share',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              content: Text(
                                e.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              actionsAlignment: MainAxisAlignment.center,
                              actions: [
                                SizedBox(
                                  width: 120,
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: adminAccentGold,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text(
                                      'OK',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Share',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        try {
                          final result = await OpenFilex.open(path);
                          if (!mounted) return;
                          if (result.type != ResultType.done) {
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                title: const Text(
                                  'Unable to open',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                content: Text(
                                  result.message.trim().isNotEmpty
                                      ? result.message.trim()
                                      : 'No app available to open this file.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                actionsAlignment: MainAxisAlignment.center,
                                actions: [
                                  SizedBox(
                                    width: 120,
                                    child: ElevatedButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: adminAccentGold,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'OK',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              title: const Text(
                                'Unable to open',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              content: Text(
                                e.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              actionsAlignment: MainAxisAlignment.center,
                              actions: [
                                SizedBox(
                                  width: 120,
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: adminAccentGold,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text(
                                      'OK',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: adminAccentGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Open',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        return;
      }

      final saveLocation = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [pdfType],
      );
      if (saveLocation == null) return;

      final file = XFile.fromData(
        bytes,
        name: fileName,
        mimeType: 'application/pdf',
      );
      await file.saveTo(saveLocation.path);
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      String message = e.toString();
      if (e is FirebaseFunctionsException) {
        final details = <String>[
          e.code,
          if ((e.message ?? '').trim().isNotEmpty) e.message!.trim(),
        ].where((v) => v.trim().isNotEmpty).join(': ');
        if (details.isNotEmpty) message = details;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Report failed',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: adminAccentGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _monthRange(_selectedMonth);
    final startTs = Timestamp.fromDate(range.start);
    final endTs = Timestamp.fromDate(range.end);

    final clientsCountStream = _countStream(
      _db
          .collection('users')
          .where('created_at', isGreaterThanOrEqualTo: startTs)
          .where('created_at', isLessThan: endTs),
      refreshEvery: const Duration(seconds: 20),
    );
    final caregiversCountStream = _countStream(
      _db
          .collection('caregivers')
          .where('created_at', isGreaterThanOrEqualTo: startTs)
          .where('created_at', isLessThan: endTs),
      refreshEvery: const Duration(seconds: 20),
    );

    final usersStream = _db
        .collection('users')
        .where('created_at', isGreaterThanOrEqualTo: startTs)
        .where('created_at', isLessThan: endTs)
        .limit(200)
        .snapshots();
    final caregiversStream = _db
        .collection('caregivers')
        .where('created_at', isGreaterThanOrEqualTo: startTs)
        .where('created_at', isLessThan: endTs)
        .limit(200)
        .snapshots();

    final headerWithAnalytics = SizedBox(
      height: _heroHeight + _headerCardOverlap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(height: _heroHeight),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeroCover()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: _MonthlyUsersAnalyticsCard(
              monthLabel: _monthLabel(_selectedMonth),
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onGenerateReport: _generateMonthlyUsersReport,
              clientsCountStream: clientsCountStream,
              caregiversCountStream: caregiversCountStream,
            ),
          ),
        ],
      ),
    );

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panelBackdropAlpha =
        (lerpDouble(0.0, 0.08, _panelController.value) ?? 0.0)
            .clamp(0.0, 0.12)
            .toDouble();

    final content = Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [headerWithAnalytics],
        ),
        if (panelBackdropAlpha > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                color: Colors.black.withValues(alpha: panelBackdropAlpha),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              opacity: _modalSheetScrimVisible ? 1 : 0,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.54),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final headerHeight = _heroHeight + _headerCardOverlap;
            final desiredTopGap = 12.0;
            final panelMinExtent =
                ((screenHeight - (headerHeight + desiredTopGap)) / screenHeight)
                    .clamp(0.30, 0.70)
                    .toDouble();
            final denom = (_panelMaxExtent - panelMinExtent).clamp(0.0, 1.0);
            final desiredInitialT = 0.0;

            if (!_panelSeeded ||
                (!_panelUserInteracted &&
                    (_panelController.value - desiredInitialT).abs() > 0.001)) {
              _panelSeeded = true;
              _pendingPanelSeedValue = desiredInitialT;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_panelUserInteracted) return;
                final seed = _pendingPanelSeedValue;
                if (seed == null) return;
                _panelController.value = seed;
              });
            }

            final extentBase =
                panelMinExtent + (denom * _panelController.value);
            final t = denom <= 0 ? 0.0 : _panelController.value;
            final appBarT = ((extentBase - 0.90) / 0.10)
                .clamp(0.0, 1.0)
                .toDouble();
            final topChromeInset =
                (lerpDouble(0, kToolbarHeight + 6.0, appBarT) ?? 0.0).clamp(
                  0.0,
                  double.infinity,
                );

            final panelHeight = (extentBase * screenHeight)
                .clamp(0.0, screenHeight)
                .toDouble();
            final dragRangePx = (denom.abs() * screenHeight)
                .clamp(1.0, double.infinity)
                .toDouble();

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                height: panelHeight,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border.all(
                      color: Colors.black.withValues(
                        alpha: (lerpDouble(0.05, 0.07, t) ?? 0.06).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (lerpDouble(0.14, 0.22, t) ?? 0.14).clamp(
                            0.0,
                            1.0,
                          ),
                        ),
                        blurRadius: (lerpDouble(18, 26, t) ?? 22).clamp(
                          0.0,
                          double.infinity,
                        ),
                        offset: Offset(
                          0,
                          -((lerpDouble(6, 10, t) ?? 8).clamp(
                            0.0,
                            double.infinity,
                          )),
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: topChromeInset),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onVerticalDragUpdate: (details) =>
                            _onPanelHandleDragUpdate(
                              details.delta.dy,
                              dragRangePx,
                            ),
                        onVerticalDragEnd: (details) =>
                            _onPanelHandleDragEnd(details.primaryVelocity ?? 0),
                        onVerticalDragCancel: () => _onPanelHandleDragEnd(0),
                        child: SizedBox(
                          height: 44,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: usersStream,
                              builder: (context, usersSnap) {
                                return StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: caregiversStream,
                                  builder: (context, caregiversSnap) {
                                    return ListView(
                                      controller: _panelScrollController,
                                      padding: EdgeInsets.only(
                                        bottom: (bottomInset + 24).clamp(
                                          24.0,
                                          64.0,
                                        ),
                                      ),
                                      physics: const ClampingScrollPhysics(),
                                      children: [
                                        _UsersSearchField(
                                          controller: _searchController,
                                        ),
                                        const SizedBox(height: 10),
                                        _UsersFilterBar(
                                          selectedIndex: _tabController.index,
                                          onSelected: (index) {
                                            _tabController.index = index;
                                          },
                                        ),
                                        Transform.translate(
                                          offset: const Offset(0, -60),
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 5,
                                            ),
                                            child: _UsersListBody(
                                              tabIndex: _tabController.index,
                                              searchClients: _searchClients,
                                              searchCaregivers:
                                                  _searchCaregivers,
                                              searchAll: _searchAll,
                                              usersSnapshot: usersSnap,
                                              caregiversSnapshot:
                                                  caregiversSnap,
                                              onView: (entry) => unawaited(
                                                _openUserDetailsSheet(entry),
                                              ),
                                              onEdit: (entry) => unawaited(
                                                _openUserEditSheet(entry),
                                              ),
                                              onDelete: (entry) =>
                                                  unawaited(_deleteUser(entry)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: buildProfileStyleAppBar(title: 'Users'),
      body: content,
    );
  }
}

InputDecoration _sheetFieldDecoration(String labelText, {Widget? suffixIcon}) {
  return InputDecoration(
    labelText: labelText,
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.black.withValues(alpha: 0.55),
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    suffixIcon: suffixIcon,
  );
}

class _AdminUserDetailsSheet extends StatefulWidget {
  const _AdminUserDetailsSheet({required this.entry});

  final _AdminUserEntry entry;

  @override
  State<_AdminUserDetailsSheet> createState() => _AdminUserDetailsSheetState();
}

class _AdminUserDetailsSheetState extends State<_AdminUserDetailsSheet> {
  int _selectedTabIndex = 0;
  int? _selectedRatingFilter;
  final Map<String, Future<_UserMini>> _reviewUserCache = {};
  DateTime? _scheduleSelectedDay;
  final Map<String, List<_ScheduleTimeRange>> _scheduleTakenCache = {};
  final Set<String> _scheduleLoadingTaken = <String>{};

  List<String> _tabLabelsForRole(_AdminUserType type) {
    if (type == _AdminUserType.caregiver) {
      return const <String>[
        'Caregiver details',
        'Reviews',
        'Documents',
        'Schedule',
      ];
    }
    return const <String>[
      'Client details',
      'Emergency contact',
      'Family details',
    ];
  }

  String _string(dynamic value) => value?.toString().trim() ?? '';

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  TimeOfDay? _parseStoredTime(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;
    final hm = normalized.split(':');
    if (hm.length >= 2) {
      final hour = int.tryParse(hm[0]);
      final minute = int.tryParse(hm[1]);
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
      }
    }
    try {
      final t = DateFormat('h:mm a').parseLoose(normalized.toUpperCase());
      return TimeOfDay(hour: t.hour, minute: t.minute);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay _endTimeFromStart(TimeOfDay startTime) {
    final totalMinutes = (startTime.hour * 60) + startTime.minute + 120;
    final clamped = totalMinutes.clamp(0, 24 * 60 - 1);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  Future<List<_ScheduleTimeRange>> _fetchTakenRanges({
    required String caregiverId,
    required DateTime day,
  }) async {
    try {
      final ymd = _ymd(day);
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('caregiverId', isEqualTo: caregiverId)
          .get();

      const allowedStatuses = <String>{
        'ASSIGNED',
        'SCHEDULED',
        'PENDING',
        'READY',
        'ONGOING',
        'IN_PROGRESS',
        'NOTIFY',
        'HANDLE_CLIENT',
        'MISSING',
        'COMPLETED',
      };

      bool matchesDay(dynamic value) {
        if (value == null) return false;
        if (value is Timestamp) return _ymd(value.toDate()) == ymd;
        final raw = value.toString().trim();
        return raw.isNotEmpty && raw == ymd;
      }

      final ranges = <_ScheduleTimeRange>[];
      final seen = <String>{};
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        final status = (data['status']?.toString().trim() ?? '').toUpperCase();
        if (status.isEmpty) continue;
        if (status == 'EMERGENCY_ALERT') continue;
        if (status.startsWith('CANCEL')) continue;
        if (!allowedStatuses.contains(status)) continue;
        if (!matchesDay(data['scheduledDate']) && !matchesDay(data['date'])) {
          continue;
        }
        final start =
            _parseStoredTime(data['startTime']?.toString() ?? '') ??
            _parseStoredTime(data['time']?.toString() ?? '');
        if (start == null) continue;
        var end = _parseStoredTime(data['endTime']?.toString() ?? '');
        end ??= _endTimeFromStart(start);
        final sMin = start.hour * 60 + start.minute;
        final eMin = end.hour * 60 + end.minute;
        if (eMin <= sMin) end = _endTimeFromStart(start);
        ranges.add(_ScheduleTimeRange(start: start, end: end));
      }
      ranges.sort((a, b) {
        final aMin = a.start.hour * 60 + a.start.minute;
        final bMin = b.start.hour * 60 + b.start.minute;
        return aMin.compareTo(bMin);
      });
      return ranges;
    } catch (_) {
      return const <_ScheduleTimeRange>[];
    }
  }

  List<Map<String, dynamic>> _extractListOfMaps(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _extractEmergencyContacts(
    Map<String, dynamic> data,
  ) {
    return _extractListOfMaps(data['emergencyContacts']);
  }

  List<Map<String, dynamic>> _extractFamilyDetails(Map<String, dynamic> data) {
    return _extractListOfMaps(data['address']);
  }

  String _formatRelative(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo';
    if (diff.inDays >= 7) return '${diff.inDays ~/ 7}w';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'Now';
  }

  String _formatReviewDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    try {
      return DateFormat('yyyy-MM-dd').format(timestamp.toDate());
    } catch (_) {
      return '';
    }
  }

  int _coerceRating(dynamic value) {
    if (value is int) return value.clamp(1, 5);
    if (value is double) return value.round().clamp(1, 5);
    if (value is num) return value.toInt().clamp(1, 5);
    if (value is String) return (int.tryParse(value.trim()) ?? 0).clamp(1, 5);
    return 0;
  }

  Future<_UserMini> _fetchUserMini({
    required String userId,
    required String fallbackName,
  }) {
    if (userId.trim().isEmpty) {
      return Future<_UserMini>.value(
        _UserMini(name: fallbackName, photoUrl: null),
      );
    }
    return _reviewUserCache.putIfAbsent(userId, () async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snap.data() ?? const <String, dynamic>{};
        final name = _string(data['name']);
        final photoUrl = _string(data['photoUrl']);
        return _UserMini(
          name: name.isNotEmpty ? name : fallbackName,
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        );
      } catch (_) {
        return _UserMini(name: fallbackName, photoUrl: null);
      }
    });
  }

  Widget _starRow(double rating, {double size = 16}) {
    final clamped = rating.clamp(0.0, 5.0);
    final full = clamped.floor();
    final half = (clamped - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;
    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star_rounded, size: size, color: adminAccentGold));
    }
    if (half == 1) {
      stars.add(
        Icon(Icons.star_half_rounded, size: size, color: adminAccentGold),
      );
    }
    for (var i = 0; i < empty; i++) {
      stars.add(
        Icon(
          Icons.star_border_rounded,
          size: size,
          color: Colors.black.withValues(alpha: 0.18),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _ratingBar({
    required int star,
    required int count,
    required int total,
  }) {
    final fraction = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            star.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.72),
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: (total > 0 && count > 0)
                    ? math.max(fraction, 0.03)
                    : 0.0,
                backgroundColor: Colors.black.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  adminAccentGold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    Widget content = Text(label);
    final trimmed = label.trim();
    final firstToken = trimmed.split(' ').first;
    final rating = int.tryParse(firstToken);
    if (rating != null && rating >= 1 && rating <= 5) {
      final rest = trimmed.substring(firstToken.length).trim();
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rating.toString()),
          const SizedBox(width: 4),
          const Icon(Icons.star_rounded, size: 14, color: adminAccentGold),
          if (rest.isNotEmpty) ...[const SizedBox(width: 4), Text(rest)],
        ],
      );
    }

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.black : _profileDarkText,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected
                ? adminAccentGold
                : Colors.black.withValues(alpha: 0.12),
            width: 1.1,
          ),
        ),
        backgroundColor: selected ? adminAccentGold : Colors.white,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
      child: content,
    );
  }

  Widget _reviewAvatar(_UserMini user) {
    final trimmed = user.photoUrl?.trim();
    if (trimmed?.isNotEmpty == true) {
      return Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(1.8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _usersDetailsAvatarOutlineColor,
            width: 2.2,
          ),
        ),
        child: ClipOval(
          child: SafeNetworkImage(
            trimmed!,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
        ),
      );
    }

    final name = user.name.trim();
    final initial = name.isEmpty ? 'U' : name[0].toUpperCase();
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(1.8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _usersDetailsAvatarOutlineColor, width: 2.2),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.black.withValues(alpha: 0.08),
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: _profileDarkText,
          ),
        ),
      ),
    );
  }

  Widget _buildCaregiverReply({
    required String caregiverName,
    required String? caregiverPhotoUrl,
    required String reply,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(1.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _usersDetailsAvatarOutlineColor,
                    width: 2,
                  ),
                ),
                child: DefaultProfileAvatar(
                  radius: 12.6,
                  photoUrl: caregiverPhotoUrl,
                  label: caregiverName,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  caregiverName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withValues(alpha: 0.70),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reply,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: _profileDarkText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final entry = widget.entry;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        builder: (sheetContext, controller) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'User details',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: entry.ref.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const _UsersDetailsPlaceholder(
                          message: 'Details unavailable',
                          explanation: 'Unable to load user details right now.',
                          centerVertically: true,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 26),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final data =
                          snapshot.data!.data() ?? const <String, dynamic>{};
                      final labels = _tabLabelsForRole(entry.type);
                      final selectedIndex = _selectedTabIndex
                          .clamp(0, labels.length - 1)
                          .toInt();
                      final displayName = _string(data['name']).isNotEmpty
                          ? _string(data['name'])
                          : entry.name;
                      final photoUrl = _string(data['photoUrl']).isNotEmpty
                          ? _string(data['photoUrl'])
                          : entry.photoUrl;

                      Widget selectedTabContent() {
                        if (entry.type == _AdminUserType.caregiver) {
                          if (selectedIndex == 0) {
                            final caregiverId = entry.id.trim();
                            final caregiverName = displayName;
                            final caregiverPhotoUrl =
                                _string(data['photoUrl']).isNotEmpty
                                ? _string(data['photoUrl'])
                                : (_string(data['imageUrl']).isNotEmpty
                                      ? _string(data['imageUrl'])
                                      : photoUrl);
                            final caregiverPhone =
                                _string(data['phone']).isNotEmpty
                                ? _string(data['phone'])
                                : (_string(data['phoneNumber']).isNotEmpty
                                      ? _string(data['phoneNumber'])
                                      : '—');
                            final caregiverAddress =
                                _string(data['defaultAddress']).isNotEmpty
                                ? _string(data['defaultAddress'])
                                : (_string(data['address']).isNotEmpty
                                      ? _string(data['address'])
                                      : (_string(data['area']).isNotEmpty
                                            ? _string(data['area'])
                                            : '—'));
                            final bioRaw = _string(data['bio']);
                            final prefs = extractServicePreferencesList(
                              data['servicePreferences'] ?? data['services'],
                            );
                            final fallbackServiceLabel = _string(
                              data['service'],
                            );
                            final servicesValue = prefs.isNotEmpty
                                ? prefs.join(', ')
                                : (fallbackServiceLabel.trim().isNotEmpty
                                      ? fallbackServiceLabel.trim()
                                      : 'Unavailable');

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _UsersDetailsSectionHeader(
                                  title: 'Caregiver details',
                                ),
                                const SizedBox(height: 4),
                                _UsersDetailsAvatar(
                                  label: caregiverName,
                                  photoUrl: caregiverPhotoUrl,
                                ),
                                _UsersDetailsTabContent(
                                  children: [
                                    if (caregiverId.isNotEmpty)
                                      _UsersDetailsInfoRow(
                                        icon: Icons.badge_outlined,
                                        title: 'Caregiver ID',
                                        value: caregiverId,
                                      ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.person,
                                      title: 'Caregiver name',
                                      value: caregiverName,
                                    ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.medical_services_outlined,
                                      title: 'Services',
                                      value: servicesValue,
                                    ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.phone_android,
                                      title: 'Contact',
                                      value: caregiverPhone,
                                    ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.home,
                                      title: 'Address',
                                      value: caregiverAddress,
                                      showBorder: bioRaw.trim().isNotEmpty,
                                    ),
                                    if (bioRaw.trim().isNotEmpty)
                                      _UsersDetailsInfoContentRow(
                                        icon: Icons.info_outline,
                                        title: 'Bio',
                                        value: bioRaw.trim(),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          }

                          if (selectedIndex == 2) {
                            return _buildCaregiverDocumentsTab(
                              caregiverId: entry.id,
                            );
                          }

                          if (selectedIndex == 3) {
                            return _buildCaregiverScheduleTab(
                              caregiverId: entry.id,
                            );
                          }

                          final stream = FirebaseFirestore.instance
                              .collection('reviews')
                              .where('caregiverId', isEqualTo: entry.id)
                              .snapshots();

                          return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: stream,
                            builder: (context, reviewsSnap) {
                              if (reviewsSnap.hasError) {
                                return const _UsersDetailsPlaceholder(
                                  message: 'Reviews unavailable',
                                  explanation:
                                      'Unable to load reviews right now.',
                                  centerVertically: true,
                                );
                              }
                              if (!reviewsSnap.hasData) {
                                return const _UsersDetailsPlaceholder(
                                  message: 'Reviews unavailable',
                                  explanation: 'Loading reviews...',
                                  centerVertically: true,
                                );
                              }

                              final docs =
                                  reviewsSnap.data!.docs.toList(growable: false)
                                    ..sort((a, b) {
                                      final ta =
                                          a.data()['createdAt'] as Timestamp?;
                                      final tb =
                                          b.data()['createdAt'] as Timestamp?;
                                      if (ta == null && tb == null) return 0;
                                      if (ta == null) return 1;
                                      if (tb == null) return -1;
                                      return tb.compareTo(ta);
                                    });

                              final counts = <int, int>{
                                1: 0,
                                2: 0,
                                3: 0,
                                4: 0,
                                5: 0,
                              };
                              var totalRating = 0;
                              for (final doc in docs) {
                                final rating = _coerceRating(
                                  doc.data()['rating'],
                                );
                                if (rating <= 0) continue;
                                counts[rating] = (counts[rating] ?? 0) + 1;
                                totalRating += rating;
                              }
                              final totalCount = counts.values.fold<int>(
                                0,
                                (a, b) => a + b,
                              );
                              final average = totalCount == 0
                                  ? 0.0
                                  : totalRating / totalCount;

                              final selected = _selectedRatingFilter;
                              final visibleDocs = selected == null
                                  ? docs
                                  : docs
                                        .where(
                                          (d) =>
                                              _coerceRating(
                                                d.data()['rating'],
                                              ) ==
                                              selected,
                                        )
                                        .toList(growable: false);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _UsersDetailsSectionHeader(
                                    title: 'Reviews',
                                  ),
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.black.withValues(
                                          alpha: 0.12,
                                        ),
                                        width: 1.2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x1A000000),
                                          blurRadius: 16,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      14,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 124,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                average.toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w900,
                                                  color: _profileDarkText,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _starRow(average, size: 16),
                                              const SizedBox(height: 10),
                                              Text(
                                                '$totalCount ratings',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.black
                                                      .withValues(alpha: 0.55),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              for (final star in const [
                                                5,
                                                4,
                                                3,
                                                2,
                                                1,
                                              ])
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: star == 1 ? 0 : 10,
                                                  ),
                                                  child: _ratingBar(
                                                    star: star,
                                                    count: counts[star] ?? 0,
                                                    total: totalCount,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const _UsersDetailsSectionHeader(
                                    title: 'Filters',
                                  ),
                                  const SizedBox(height: 4),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      children: [
                                        _filterChip(
                                          label: 'All ($totalCount)',
                                          selected: selected == null,
                                          onTap: () => setState(
                                            () => _selectedRatingFilter = null,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        for (final star in const [
                                          5,
                                          4,
                                          3,
                                          2,
                                          1,
                                        ]) ...[
                                          _filterChip(
                                            label:
                                                '$star (${counts[star] ?? 0})',
                                            selected: selected == star,
                                            onTap: () => setState(
                                              () =>
                                                  _selectedRatingFilter = star,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (totalCount == 0)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: _UsersDetailsPlaceholder(
                                        message: 'Reviews unavailable',
                                        explanation: 'No reviews yet.',
                                      ),
                                    )
                                  else if (visibleDocs.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: _UsersDetailsPlaceholder(
                                        message: 'Reviews unavailable',
                                        explanation:
                                            'No reviews for this filter.',
                                      ),
                                    )
                                  else
                                    ListView.separated(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: visibleDocs.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final review = visibleDocs[index]
                                            .data();
                                        final personName =
                                            _string(
                                              review['personName'],
                                            ).isNotEmpty
                                            ? _string(review['personName'])
                                            : 'User';
                                        final userId = _string(
                                          review['userId'],
                                        );
                                        final service = _string(
                                          review['service'],
                                        );
                                        final feedback = _string(
                                          review['feedback'],
                                        );
                                        final caregiverReply = _string(
                                          review['caregiverReply'],
                                        );
                                        final rating = _coerceRating(
                                          review['rating'],
                                        ).toDouble();
                                        final createdAt =
                                            review['createdAt'] as Timestamp?;
                                        final relative = _formatRelative(
                                          createdAt,
                                        );
                                        final dateLabel = _formatReviewDate(
                                          createdAt,
                                        );

                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                              width: 1.2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x1A000000),
                                                blurRadius: 16,
                                                offset: Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            12,
                                            12,
                                            10,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              FutureBuilder<_UserMini>(
                                                future: _fetchUserMini(
                                                  userId: userId,
                                                  fallbackName: personName,
                                                ),
                                                builder: (context, userSnap) {
                                                  final user =
                                                      userSnap.data ??
                                                      _UserMini(
                                                        name: personName,
                                                        photoUrl: null,
                                                      );
                                                  return Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      _reviewAvatar(user),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          user.name
                                                                  .trim()
                                                                  .isNotEmpty
                                                              ? user.name.trim()
                                                              : personName,
                                                          style: const TextStyle(
                                                            fontSize: 12.5,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color:
                                                                _profileDarkText,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              _starRow(rating, size: 16),
                                              if (service.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Service: $service',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.58,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 10),
                                              Text(
                                                feedback.isNotEmpty
                                                    ? feedback
                                                    : 'No written feedback.',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  height: 1.35,
                                                  fontWeight: FontWeight.w700,
                                                  color: feedback.isNotEmpty
                                                      ? _profileDarkText
                                                      : Colors.black.withValues(
                                                          alpha: 0.52,
                                                        ),
                                                ),
                                              ),
                                              if (caregiverReply
                                                  .trim()
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                _buildCaregiverReply(
                                                  caregiverName: displayName,
                                                  caregiverPhotoUrl: photoUrl,
                                                  reply: caregiverReply.trim(),
                                                ),
                                              ],
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  Text(
                                                    relative.isNotEmpty
                                                        ? relative
                                                        : dateLabel,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.45,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              );
                            },
                          );
                        }

                        if (selectedIndex == 0) {
                          final phone = _string(data['phone']).isNotEmpty
                              ? _string(data['phone'])
                              : entry.phone;
                          final address =
                              _string(data['defaultAddress']).isNotEmpty
                              ? _string(data['defaultAddress'])
                              : (_string(data['address']).isNotEmpty
                                    ? _string(data['address'])
                                    : entry.defaultAddress);

                          final ownerName = displayName;
                          final ownerPhotoUrl =
                              _string(data['profile_photo']).isNotEmpty
                              ? _string(data['profile_photo'])
                              : (_string(data['photoUrl']).isNotEmpty
                                    ? _string(data['photoUrl'])
                                    : (_string(data['imageUrl']).isNotEmpty
                                          ? _string(data['imageUrl'])
                                          : (entry.photoUrl ?? '')));
                          final ownerPhone = phone.trim().isNotEmpty
                              ? phone.trim()
                              : '—';
                          final careLocation = address.trim().isNotEmpty
                              ? address.trim()
                              : '—';
                          var personName = _string(data['defaultPerson']);
                          var personLabel = 'Care recipient';
                          if (personName.trim().isEmpty) {
                            final family = _extractFamilyDetails(data);
                            Map<String, dynamic>? defaultEntry;
                            for (final e in family) {
                              if (e['isDefault'] == true) {
                                defaultEntry = e;
                                break;
                              }
                            }
                            defaultEntry ??= family.isNotEmpty
                                ? family.first
                                : null;
                            if (defaultEntry != null) {
                              final name = _string(defaultEntry['name']);
                              if (name.isNotEmpty) personName = name;
                              final label = _string(defaultEntry['label']);
                              if (label.isNotEmpty) personLabel = label;
                            }
                          }
                          final primaryPersonValue =
                              personName.trim().isNotEmpty
                              ? '$personName (${personLabel.trim().isEmpty ? '—' : personLabel.trim()})'
                              : '—';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _UsersDetailsSectionHeader(
                                title: 'Client details',
                              ),
                              const SizedBox(height: 4),
                              _UsersDetailsAvatar(
                                label: ownerName,
                                photoUrl: ownerPhotoUrl,
                              ),
                              _UsersDetailsTabContent(
                                children: [
                                  _UsersDetailsInfoRow(
                                    icon: Icons.person,
                                    title: 'Client name',
                                    value: ownerName,
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.phone_android,
                                    title: 'Client contact',
                                    value: ownerPhone,
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.home,
                                    title: 'Care location',
                                    value: careLocation,
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.accessibility_new_rounded,
                                    title: 'Primary person',
                                    value: primaryPersonValue,
                                    showBorder: false,
                                  ),
                                ],
                              ),
                            ],
                          );
                        }

                        if (selectedIndex == 1) {
                          final contacts = _extractEmergencyContacts(data);
                          if (contacts.isEmpty) {
                            return const _UsersDetailsPlaceholder(
                              message: 'Emergency contacts unavailable',
                              explanation:
                                  'Client has not added any emergency contacts yet.',
                              centerVertically: true,
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _UsersDetailsSectionHeader(
                                title: 'Emergency contact',
                                hint: 'Contacts provided by the client.',
                              ),
                              for (var i = 0; i < contacts.length; i++) ...[
                                const SizedBox(height: 4),
                                _UsersDetailsAvatar(
                                  label: _string(contacts[i]['name']).isNotEmpty
                                      ? _string(contacts[i]['name'])
                                      : 'Emergency contact',
                                  photoUrl: _string(contacts[i]['photoUrl']),
                                ),
                                _UsersDetailsTabContent(
                                  children: [
                                    _UsersDetailsInfoRow(
                                      icon: Icons.person,
                                      title: 'Name',
                                      value:
                                          _string(
                                            contacts[i]['name'],
                                          ).isNotEmpty
                                          ? _string(contacts[i]['name'])
                                          : 'Emergency contact',
                                    ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.family_restroom_rounded,
                                      title: 'Relationship',
                                      value:
                                          _string(
                                            contacts[i]['relationship'],
                                          ).isNotEmpty
                                          ? _string(contacts[i]['relationship'])
                                          : 'Relationship not set',
                                    ),
                                    _UsersDetailsInfoRow(
                                      icon: Icons.phone_android,
                                      title: 'Contact',
                                      value:
                                          _string(
                                            contacts[i]['phone'],
                                          ).isNotEmpty
                                          ? _string(contacts[i]['phone'])
                                          : 'Phone not available',
                                      showBorder: false,
                                    ),
                                  ],
                                ),
                                if (i != contacts.length - 1)
                                  const SizedBox(height: 12),
                              ],
                            ],
                          );
                        }

                        final family = _extractFamilyDetails(data).toList()
                          ..sort((a, b) {
                            final ad = a['isDefault'] == true;
                            final bd = b['isDefault'] == true;
                            if (ad == bd) return 0;
                            return ad ? -1 : 1;
                          });
                        if (family.isEmpty) {
                          return const _UsersDetailsPlaceholder(
                            message: 'Family details unavailable',
                            explanation:
                                'Client has not added any family details yet.',
                            centerVertically: true,
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _UsersDetailsSectionHeader(
                              title: 'Family details',
                              hint: 'Family addresses provided by the client.',
                            ),
                            for (var i = 0; i < family.length; i++) ...[
                              const SizedBox(height: 4),
                              _UsersDetailsAvatar(
                                label: _string(family[i]['name']).isNotEmpty
                                    ? _string(family[i]['name'])
                                    : 'Family member',
                                photoUrl: _string(family[i]['photoUrl']),
                              ),
                              _UsersDetailsTabContent(
                                children: [
                                  _UsersDetailsInfoRow(
                                    icon: Icons.person,
                                    title: 'Name',
                                    value: _string(family[i]['name']).isNotEmpty
                                        ? _string(family[i]['name'])
                                        : '-',
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.family_restroom_rounded,
                                    title: 'Relationship',
                                    value:
                                        _string(family[i]['label']).isNotEmpty
                                        ? _string(family[i]['label'])
                                        : 'Relationship not set',
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.phone_android,
                                    title: 'Contact',
                                    value:
                                        _string(family[i]['phone']).isNotEmpty
                                        ? _string(family[i]['phone'])
                                        : 'Phone not available',
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.home,
                                    title: 'Address',
                                    value:
                                        _string(family[i]['address']).isNotEmpty
                                        ? _string(family[i]['address'])
                                        : '-',
                                  ),
                                  _UsersDetailsInfoRow(
                                    icon: Icons.bookmark_rounded,
                                    title: 'Default',
                                    value: family[i]['isDefault'] == true
                                        ? 'Yes'
                                        : 'No',
                                    showBorder: false,
                                  ),
                                ],
                              ),
                              if (i != family.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _UsersDetailsTabs(
                            labels: labels,
                            selectedIndex: selectedIndex,
                            onSelected: (index) {
                              if (_selectedTabIndex == index) return;
                              setState(() => _selectedTabIndex = index);
                            },
                          ),
                          selectedTabContent(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaregiverDocumentsTab({required String caregiverId}) {
    final uid = caregiverId.trim();
    final documentsStream = uid.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('documents')
              .where('caregiverId', isEqualTo: uid)
              .snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _UsersDetailsSectionHeader(title: 'Documents'),
        const SizedBox(height: 6),
        _VerificationDocumentsCard(stream: documentsStream),
      ],
    );
  }

  Widget _buildCaregiverScheduleTab({required String caregiverId}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = _scheduleSelectedDay ?? today;
    final selectedKey = _ymd(selectedDay);
    _scheduleSelectedDay ??= today;

    final availabilityStream = caregiverId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('availability')
              .doc(caregiverId)
              .snapshots()
        : const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

    Widget eventCard({
      required String title,
      required String subtitle,
      required Color background,
      required Color foreground,
      IconData? icon,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: foreground),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: foreground.withValues(alpha: 0.78),
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget dateStrip(DateTime selected) {
      final start = selected.subtract(const Duration(days: 3));
      final days = List<DateTime>.generate(
        7,
        (i) => DateTime(start.year, start.month, start.day + i),
      );
      final monthLabel = DateFormat('MMM').format(selected);

      return Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              monthLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black.withValues(alpha: 0.60),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final d = days[index];
                  final isPast = d.isBefore(today);
                  final isSelected =
                      d.year == selected.year &&
                      d.month == selected.month &&
                      d.day == selected.day;
                  final weekday = DateFormat('EEE').format(d);
                  final dayNum = d.day.toString().padLeft(2, '0');

                  return InkWell(
                    onTap: () => setState(() => _scheduleSelectedDay = d),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 54,
                      decoration: BoxDecoration(
                        color: isSelected ? _primaryBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isSelected
                            ? const [
                                BoxShadow(
                                  color: Color(0x24000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            weekday,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.black.withValues(
                                      alpha: isPast ? 0.32 : 0.45,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dayNum,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              color: isSelected
                                  ? Colors.white
                                  : (isPast
                                        ? Colors.black.withValues(alpha: 0.45)
                                        : _profileDarkText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    Widget bookedTimelineDayView({
      required TimeOfDay windowStart,
      required TimeOfDay windowEnd,
      required List<_ScheduleTimeRange> taken,
    }) {
      int toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
      int floorToHour(int m) => (m ~/ 60) * 60;
      int ceilToHour(int m) => ((m + 59) ~/ 60) * 60;
      String labelForMinute(int m) {
        final h = (m ~/ 60).clamp(0, 23);
        final min = (m % 60).clamp(0, 59);
        final dt = DateTime(2000, 1, 1, h, min);
        return DateFormat('h a').format(dt).toLowerCase();
      }

      const palette = <Color>[
        Color(0xFF4F5BFF),
        Color(0xFFFFB930),
        Color(0xFF2ECC71),
        Color(0xFF7E57C2),
      ];

      final blocks = <({int start, int end, Color color, String title})>[];
      for (int i = 0; i < taken.length; i++) {
        final r = taken[i];
        final s = toMinutes(r.start);
        final e = toMinutes(r.end);
        if (e <= s) continue;
        blocks.add((
          start: s,
          end: e,
          color: palette[i % palette.length],
          title: 'Booked',
        ));
      }

      final baseStart = toMinutes(windowStart);
      final baseEnd = toMinutes(windowEnd);
      final startMin = floorToHour(baseStart);
      final endMin = ceilToHour(baseEnd);
      final hourCount = ((endMin - startMin) / 60).ceil().clamp(1, 48);
      final pxPerMin = 0.85;

      int lanesFor(List<({int start, int end})> spans) {
        final sorted = spans.toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        final laneEnds = <int>[];
        for (final s in sorted) {
          var placed = false;
          for (int i = 0; i < laneEnds.length; i++) {
            if (s.start >= laneEnds[i]) {
              laneEnds[i] = s.end;
              placed = true;
              break;
            }
          }
          if (!placed) laneEnds.add(s.end);
        }
        return laneEnds.length.clamp(1, 4);
      }

      final lanes = lanesFor([
        for (final b in blocks) (start: b.start, end: b.end),
      ]);

      final sorted = blocks.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final laneEnds = List<int>.filled(lanes, -999999);
      final laidOut =
          <({int start, int end, Color color, String title, int lane})>[];
      for (final b in sorted) {
        int lane = 0;
        for (int i = 0; i < laneEnds.length; i++) {
          if (b.start >= laneEnds[i]) {
            lane = i;
            break;
          }
          lane = i;
        }
        laneEnds[lane] = b.end;
        laidOut.add((
          start: b.start,
          end: b.end,
          color: b.color,
          title: b.title,
          lane: lane,
        ));
      }

      final totalHeight = (hourCount * 60 * pxPerMin).toDouble();

      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SizedBox(
          height: totalHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: SizedBox(
                  height: totalHeight,
                  child: Column(
                    children: [
                      for (int i = 0; i <= hourCount; i++)
                        SizedBox(
                          height: i == hourCount ? 0 : 60 * pxPerMin,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                labelForMinute(startMin + (i * 60)),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final laneGap = 8.0;
                    final laneWidth =
                        (c.maxWidth - (laneGap * (lanes - 1))) / lanes;
                    return SizedBox(
                      height: totalHeight,
                      child: Stack(
                        children: [
                          for (int i = 0; i <= hourCount; i++)
                            Positioned(
                              top: i * 60 * pxPerMin,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 1,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          for (final e in laidOut)
                            Positioned(
                              top: (e.start - startMin) * pxPerMin,
                              left: e.lane * (laneWidth + laneGap),
                              width: laneWidth,
                              height: ((e.end - e.start) * pxPerMin).clamp(
                                18.0,
                                9999.0,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: e.color,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x24000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${labelForMinute(e.start)} - ${labelForMinute(e.end)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: availabilityStream,
      builder: (context, availabilitySnap) {
        final availability =
            availabilitySnap.data?.data() ?? const <String, dynamic>{};

        List<DateTimeRange> blockedRanges() {
          final raw = availability['blockedDates'];
          if (raw is! Iterable) return const [];
          final ranges = <DateTimeRange>[];
          for (final entry in raw) {
            if (entry is! Map) continue;
            final startRaw = entry['start']?.toString();
            final endRaw = entry['end']?.toString();
            final start = startRaw == null ? null : DateTime.tryParse(startRaw);
            final end = endRaw == null ? null : DateTime.tryParse(endRaw);
            if (start == null || end == null) continue;
            ranges.add(
              DateTimeRange(
                start: DateTime(start.year, start.month, start.day),
                end: DateTime(end.year, end.month, end.day),
              ),
            );
          }
          return ranges;
        }

        Map<int, ({bool available, TimeOfDay start, TimeOfDay end})>
        weeklyRanges() {
          const dayToWeekday = <String, int>{
            'Monday': DateTime.monday,
            'Tuesday': DateTime.tuesday,
            'Wednesday': DateTime.wednesday,
            'Thursday': DateTime.thursday,
            'Friday': DateTime.friday,
            'Saturday': DateTime.saturday,
            'Sunday': DateTime.sunday,
          };
          final raw = availability['weeklySchedule'];
          if (raw is! Iterable) return const {};
          final map =
              <int, ({bool available, TimeOfDay start, TimeOfDay end})>{};
          for (final entry in raw) {
            if (entry is! Map) continue;
            final dayName = entry['day']?.toString();
            final weekday = dayToWeekday[dayName];
            if (weekday == null) continue;
            final availableFlag = entry['available'] as bool? ?? true;
            final startRaw = entry['start']?.toString() ?? '08:00';
            final endRaw = entry['end']?.toString() ?? '18:00';
            final start =
                _parseStoredTime(startRaw) ??
                const TimeOfDay(hour: 8, minute: 0);
            final end =
                _parseStoredTime(endRaw) ??
                const TimeOfDay(hour: 18, minute: 0);
            map[weekday] = (available: availableFlag, start: start, end: end);
          }
          return map;
        }

        final blockedRangesValue = blockedRanges();
        final weeklyValue = weeklyRanges();
        final normalizedDay = DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        );
        final blockedByDates = blockedRangesValue.any((r) {
          final start = DateTime(r.start.year, r.start.month, r.start.day);
          final end = DateTime(r.end.year, r.end.month, r.end.day);
          return !normalizedDay.isBefore(start) && !normalizedDay.isAfter(end);
        });
        final blocked = blockedByDates;

        final weekly = weeklyValue[normalizedDay.weekday];
        final availableWindow = (weekly == null || !weekly.available)
            ? null
            : (weekly.start, weekly.end);
        final dayOff = weekly != null && !weekly.available;

        if (caregiverId.isNotEmpty &&
            !_scheduleTakenCache.containsKey(selectedKey) &&
            !_scheduleLoadingTaken.contains(selectedKey)) {
          _scheduleLoadingTaken.add(selectedKey);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final next = await _fetchTakenRanges(
              caregiverId: caregiverId,
              day: selectedDay,
            );
            if (!mounted) return;
            setState(() {
              _scheduleTakenCache[selectedKey] = next;
              _scheduleLoadingTaken.remove(selectedKey);
            });
          });
        }

        final taken =
            _scheduleTakenCache[selectedKey] ?? const <_ScheduleTimeRange>[];
        final isLoadingTaken =
            caregiverId.isNotEmpty &&
            !_scheduleTakenCache.containsKey(selectedKey);

        final header = dateStrip(selectedDay);
        final timelineItems = <Widget>[];
        if (isLoadingTaken) {
          timelineItems.add(
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          );
        } else if (blocked || dayOff || availableWindow == null) {
          timelineItems.add(
            eventCard(
              title: 'Unavailable',
              subtitle: blocked ? 'Blocked' : 'Not available',
              background: Colors.black.withValues(alpha: 0.06),
              foreground: _profileDarkText,
              icon: Icons.block_rounded,
            ),
          );
        } else {
          timelineItems.add(
            bookedTimelineDayView(
              windowStart: availableWindow.$1,
              windowEnd: availableWindow.$2,
              taken: taken,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _UsersDetailsSectionHeader(title: 'Schedule'),
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 14),
                  ...timelineItems,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UsersDetailsTabs extends StatelessWidget {
  const _UsersDetailsTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final selected = selectedIndex == index;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 124,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? adminAccentGold : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? adminAccentGold
                          : Colors.black.withValues(alpha: 0.12),
                      width: 1.1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.black
                            : Colors.black.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const Color _usersDetailsCardBorder = Color(0xFFEBEDF0);
const Color _usersDetailsCardBorderStrong = Color(0xFFE1E4EA);
const Color _usersDetailsCardShadow = Color(0x1A0B0C10);
const double _usersDetailsCardRadius = 18;
const Color _usersDetailsMutedText = Color(0xFF6B7280);
const Color _usersDetailsAvatarOutlineColor = Colors.white;

BoxDecoration _usersDetailsPremiumCardDecoration({
  double radius = _usersDetailsCardRadius,
}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _usersDetailsCardBorderStrong),
    boxShadow: const [
      BoxShadow(
        color: _usersDetailsCardShadow,
        blurRadius: 12,
        offset: Offset(0, 6),
      ),
    ],
  );
}

const TextStyle _usersDetailsSectionHeaderTextStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _profileDarkText,
  letterSpacing: -0.15,
);

const TextStyle _usersDetailsFieldLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: _usersDetailsMutedText,
);

const TextStyle _usersDetailsFieldValueTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: _profileDarkText,
  height: 1.25,
);

class _UsersDetailsSectionHeader extends StatelessWidget {
  const _UsersDetailsSectionHeader({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: _usersDetailsSectionHeaderTextStyle),
              ),
              if (trimmedHint.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ],
            ],
          ),
          if (trimmedHint.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              trimmedHint,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.50),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsersDetailsTabContent extends StatelessWidget {
  const _UsersDetailsTabContent({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _usersDetailsPremiumCardDecoration(),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }
}

class _UsersDetailsInfoRow extends StatelessWidget {
  const _UsersDetailsInfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.showBorder = true,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _usersDetailsCardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _usersDetailsFieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _usersDetailsFieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersDetailsInfoContentRow extends StatelessWidget {
  const _UsersDetailsInfoContentRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: _primaryBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _usersDetailsFieldLabelTextStyle),
                const SizedBox(height: 6),
                Text(value, style: _usersDetailsFieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersDetailsAvatar extends StatelessWidget {
  const _UsersDetailsAvatar({required this.label, required this.photoUrl});

  final String label;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _usersDetailsAvatarOutlineColor,
            width: 3.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: DefaultProfileAvatar(
          radius: 34,
          photoUrl: (photoUrl?.trim().isNotEmpty == true)
              ? photoUrl!.trim()
              : null,
          label: label,
        ),
      ),
    );
  }
}

class _UsersDetailsPlaceholder extends StatelessWidget {
  const _UsersDetailsPlaceholder({
    required this.message,
    required this.explanation,
    this.centerVertically = false,
  });

  final String message;
  final String explanation;
  final bool centerVertically;

  @override
  Widget build(BuildContext context) {
    final core = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 32, color: _primaryBlue),
            const SizedBox(height: 10),
            Text(
              message,
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );

    final centered = Center(child: core);
    if (!centerVertically) return centered;

    final height = (MediaQuery.sizeOf(context).height * 0.35).clamp(
      260.0,
      420.0,
    );
    return SizedBox(height: height, child: centered);
  }
}

class _UserMini {
  const _UserMini({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;
}

class _UserServiceOption {
  const _UserServiceOption({required this.label, required this.value});

  final String label;
  final String value;
}

class _AdminUserEditSheet extends StatefulWidget {
  const _AdminUserEditSheet({required this.entry});

  final _AdminUserEntry entry;

  @override
  State<_AdminUserEditSheet> createState() => _AdminUserEditSheetState();
}

class _AdminUserEditSheetState extends State<_AdminUserEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _serviceCtrl;
  late final TextEditingController _bioCtrl;

  final LayerLink _serviceFieldLink = LayerLink();
  final GlobalKey _serviceFieldKey = GlobalKey();
  OverlayEntry? _serviceOverlayEntry;
  var _serviceOptions = const <_UserServiceOption>[];
  var _servicesLoading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _emailCtrl = TextEditingController(text: widget.entry.email);
    _passwordCtrl = TextEditingController(text: '********');
    _phoneCtrl = TextEditingController(text: widget.entry.phone);
    _addressCtrl = TextEditingController(text: widget.entry.defaultAddress);
    _serviceCtrl = TextEditingController(text: '');
    _bioCtrl = TextEditingController(text: '');

    unawaited(_seedFromDoc());
    _loadServiceCatalog();
  }

  @override
  void dispose() {
    _closeServiceMenu();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _serviceCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _seedFromDoc() async {
    try {
      final snap = await widget.entry.ref.get();
      final data = snap.data() ?? const <String, dynamic>{};
      if (!mounted) return;

      final bio = (data['bio'] as String?)?.trim() ?? '';
      final email = (data['email'] as String?)?.trim() ?? '';
      final password = (data['password'] as String?)?.trim() ?? '';
      final serviceLabel = extractServiceLabelFromFirestore(data).trim();

      if (_bioCtrl.text.trim().isEmpty && bio.isNotEmpty) {
        _bioCtrl.text = bio;
      }
      if (_emailCtrl.text.trim().isEmpty && email.isNotEmpty) {
        _emailCtrl.text = email;
      }
      if (password.isNotEmpty) {
        _passwordCtrl.text = password;
      }
      if (_serviceCtrl.text.trim().isEmpty && serviceLabel.isNotEmpty) {
        _serviceCtrl.text = serviceLabel;
      }
    } catch (_) {}
  }

  Future<void> _loadServiceCatalog() async {
    if (_servicesLoading) return;
    setState(() => _servicesLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('services')
          .orderBy('name')
          .get();
      final next = <_UserServiceOption>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        next.add(_UserServiceOption(label: name, value: name));
      }
      if (!mounted) return;
      setState(() => _serviceOptions = next);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _servicesLoading = false);
    }
  }

  void _toggleServiceMenu() {
    if (_serviceOverlayEntry == null) {
      _openServiceMenu();
    } else {
      _closeServiceMenu();
    }
  }

  void _openServiceMenu() {
    _closeServiceMenu();
    final overlay = Overlay.of(context);

    final box =
        _serviceFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    final options = _serviceOptions;

    _serviceOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeServiceMenu,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _serviceFieldLink,
                  showWhenUnlinked: false,
                  offset: Offset(0, size.height + 6),
                  child: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: size.width,
                        maxWidth: size.width,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: options.isEmpty
                                  ? [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          _servicesLoading
                                              ? 'Loading services...'
                                              : 'No services available',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ]
                                  : options
                                        .map(
                                          (option) => InkWell(
                                            onTap: () => _selectService(option),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Color(
                                                            0xFFF4B63D,
                                                          ),
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      option.label,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _profileDarkText,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_serviceOverlayEntry!);
  }

  void _closeServiceMenu() {
    _serviceOverlayEntry?.remove();
    _serviceOverlayEntry = null;
  }

  void _selectService(_UserServiceOption option) {
    setState(() {
      _serviceCtrl.text = option.value;
    });
    _closeServiceMenu();
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      Object? stringOrDelete(String value) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? FieldValue.delete() : trimmed;
      }

      final updates = <String, Object?>{
        'name': stringOrDelete(_nameCtrl.text),
        'phone': stringOrDelete(_phoneCtrl.text),
        'defaultAddress': stringOrDelete(_addressCtrl.text),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final serviceValue = _serviceCtrl.text.trim();
      updates['service'] = serviceValue.isEmpty
          ? FieldValue.delete()
          : serviceValue;
      updates['servicePreferences'] = serviceValue.isEmpty
          ? FieldValue.delete()
          : <String>[serviceValue];
      if (widget.entry.type == _AdminUserType.caregiver) {
        updates['bio'] = stringOrDelete(_bioCtrl.text);
      }

      await widget.entry.ref.set(updates, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save changes. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final detailsTitle = widget.entry.type == _AdminUserType.caregiver
        ? 'Caregiver details'
        : 'Client details';

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Edit user',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      DefaultProfileAvatar(
                        radius: 34,
                        photoUrl: widget.entry.photoUrl,
                        label: widget.entry.name.isNotEmpty
                            ? widget.entry.name
                            : '?',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.entry.name.isNotEmpty
                            ? widget.entry.name
                            : 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _profileDarkText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.entry.id,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: widget.entry.id,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('User ID'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    detailsTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('Name'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailCtrl,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('Email'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordCtrl,
                    readOnly: true,
                    showCursor: false,
                    obscureText: true,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('Password'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('Contact'),
                  ),
                  const SizedBox(height: 10),
                  CompositedTransformTarget(
                    link: _serviceFieldLink,
                    child: TextFormField(
                      key: _serviceFieldKey,
                      controller: _serviceCtrl,
                      readOnly: true,
                      showCursor: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: _sheetFieldDecoration(
                        'Services',
                        suffixIcon: const Icon(Icons.expand_more, size: 18),
                      ),
                      onTap: _saving ? null : _toggleServiceMenu,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressCtrl,
                    textInputAction:
                        widget.entry.type == _AdminUserType.caregiver
                        ? TextInputAction.next
                        : TextInputAction.done,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _sheetFieldDecoration('Location'),
                  ),
                  if (widget.entry.type == _AdminUserType.caregiver) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _bioCtrl,
                      textInputAction: TextInputAction.done,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: _sheetFieldDecoration('Bio'),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    'Leave blank to delete the info.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _profileDarkText60,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: activityButtonYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerificationInfoRow extends StatelessWidget {
  const _VerificationInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.50),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value.trim().isNotEmpty ? value.trim() : '-',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerificationDocumentRow extends StatelessWidget {
  const _VerificationDocumentRow({
    required this.title,
    required this.fileName,
    required this.updatedAt,
    required this.verified,
    required this.onOpen,
  });

  final String title;
  final String fileName;
  final String updatedAt;
  final bool verified;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final statusLabel = verified ? 'Verified' : 'Pending';
    final statusColor = verified ? _primaryBlue : const Color(0xFFF4B63D);
    final statusIcon = verified
        ? Icons.check_circle_rounded
        : Icons.pending_actions_rounded;

    IconData leadingIcon() {
      final t = title.toLowerCase();
      if (t.contains('selfie')) return Icons.camera_alt_outlined;
      if (t.contains('front')) return Icons.credit_card_outlined;
      if (t.contains('back')) return Icons.credit_card_rounded;
      return Icons.description_outlined;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  leadingIcon(),
                  size: 18,
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        color: Colors.black.withValues(alpha: 0.80),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _VerificationInfoRow(label: 'File name', value: fileName),
                Divider(
                  height: 14,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                _VerificationInfoRow(label: 'Updated at', value: updatedAt),
                Divider(
                  height: 14,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                _VerificationInfoRow(label: 'Status', value: statusLabel),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onOpen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activityButtonYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerificationDocumentsCard extends StatelessWidget {
  const _VerificationDocumentsCard({required this.stream});

  final Stream<QuerySnapshot<Map<String, dynamic>>>? stream;

  Widget _shell({required Widget child}) {
    return child;
  }

  Future<void> _openDocument(BuildContext context, String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document link available.')),
      );
      return;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the document.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stream == null) {
      return _shell(
        child: const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Text(
            'No caregiver selected.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'Unable to load documents.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'No documents uploaded yet.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
            ),
          );
        }

        const requiredNames = <String>[
          'Selfie with identification card',
          'Identification card (Front)',
          'Identification card (Back)',
        ];

        DocumentSnapshot<Map<String, dynamic>>? firstByName(String name) {
          for (final d in docs) {
            final n = ((d.data()['name'] as String?) ?? '').trim();
            if (n == name) return d;
          }
          return null;
        }

        final pickedIds = <String>{};
        final orderedDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final name in requiredNames) {
          final doc = firstByName(name);
          if (doc == null) continue;
          if (!pickedIds.add(doc.id)) continue;
          orderedDocs.add(doc);
        }

        final remaining =
            <DocumentSnapshot<Map<String, dynamic>>>[
              for (final d in docs)
                if (pickedIds.add(d.id)) d,
            ]..sort((a, b) {
              final ta = (a.data()?['updatedAt'] as Timestamp?)?.toDate();
              final tb = (b.data()?['updatedAt'] as Timestamp?)?.toDate();
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });

        orderedDocs.addAll(remaining);

        Widget docItem(DocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic> docData =
              doc.data() ?? const <String, dynamic>{};
          final url = ((docData['fileUrl'] as String?) ?? '').trim();
          final updatedAtTs = docData['updatedAt'] as Timestamp?;
          return Column(
            children: [
              _VerificationDocumentRow(
                title: ((docData['name'] as String?) ?? 'Document').trim(),
                fileName: ((docData['fileName'] as String?) ?? '').trim(),
                updatedAt: updatedAtTs == null
                    ? '-'
                    : _verificationDocumentsDateFormat.format(
                        updatedAtTs.toDate(),
                      ),
                verified: (docData['status'] as bool?) == true,
                onOpen: url.isEmpty ? null : () => _openDocument(context, url),
              ),
              const SizedBox(height: 10),
            ],
          );
        }

        return _shell(
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              children: [for (final doc in orderedDocs) docItem(doc)],
            ),
          ),
        );
      },
    );
  }
}
