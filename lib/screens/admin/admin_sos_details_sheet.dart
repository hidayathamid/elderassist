import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/service_preferences.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/safe_network_image.dart';
import '../user/activity/activity_screen.dart' show activityButtonYellow;

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);
const Color _cardBorder = Color(0x14000000);
const Color _avatarOutlineColor = Colors.white;

const TextStyle _sectionHeaderTextStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w900,
  color: _profileDarkText,
);
const TextStyle _fieldLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: Colors.black54,
);
const TextStyle _fieldValueTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w800,
  color: _profileDarkText,
);

String _text(Object? value) => (value?.toString() ?? '').trim();

String _valueOrUnavailable(String value) =>
    value.trim().isNotEmpty ? value.trim() : 'Unavailable';

String _timeLabel(Object? value) {
  final ts = value is Timestamp ? value : null;
  if (ts == null) return 'Unavailable';
  final dt = ts.toDate();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

BoxDecoration _premiumCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0F000000),
        blurRadius: 16,
        offset: Offset(0, 10),
      ),
    ],
  );
}

class AdminSosDetailsSheet extends StatefulWidget {
  const AdminSosDetailsSheet({super.key, required this.sosId});

  final String sosId;

  @override
  State<AdminSosDetailsSheet> createState() => _AdminSosDetailsSheetState();
}

class _AdminSosDetailsSheetState extends State<AdminSosDetailsSheet> {
  static const labels = <String>[
    'SOS details',
    'Booking summary',
    'Caregiver details',
    'Client details',
    'Emergency contact',
  ];

  int _selectedTabIndex = 0;

  void _selectTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    bool showBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _cardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoContentRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerAvatar(String label, String? photoUrl, {double radius = 34}) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _avatarOutlineColor, width: 3.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: DefaultProfileAvatar(
          radius: radius,
          photoUrl: (photoUrl?.trim().isNotEmpty == true)
              ? photoUrl!.trim()
              : null,
          label: label,
        ),
      ),
    );
  }

  Widget _buildTabContent(List<Widget> children) {
    return Container(
      decoration: _premiumCardDecoration(),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader({required String title, String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _sectionHeaderTextStyle)),
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

  Widget _buildOtherInfoTabs() {
    final selectedIndex = _selectedTabIndex.clamp(0, labels.length - 1);
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
                onTap: () => _selectTab(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 124,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _accentGold : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? _accentGold
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

  Widget _buildUnavailablePlaceholder({
    required String message,
    String explanation = "It'll show up as soon as it becomes available.",
    bool centerVertically = false,
  }) {
    final core = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 32, color: _accentGreen),
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

  List<Map<String, dynamic>> _extractEmergencyContacts(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return const [];
    final raw = data['emergencyContacts'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    }
    return const [];
  }

  ({String name, String label, String address, String phone, String? photoUrl})
  _resolvePersonDisplay(Map<String, dynamic> sos, Map<String, dynamic>? user) {
    final targetPersonId = _text(sos['personId']).isNotEmpty
        ? _text(sos['personId'])
        : _text(sos['addressId']);

    final rawName = _text(sos['personName']).isNotEmpty
        ? _text(sos['personName'])
        : (_text(sos['selectedPersonName']).isNotEmpty
              ? _text(sos['selectedPersonName'])
              : 'Selected person');
    final rawLabel = _text(sos['selectedPersonLabel']).isNotEmpty
        ? _text(sos['selectedPersonLabel'])
        : 'Care recipient';

    final addressMetaRaw = sos['addressMeta'];
    final addressMeta = (addressMetaRaw is Map)
        ? Map<String, dynamic>.from(addressMetaRaw)
        : const <String, dynamic>{};

    final rawFamily = user?['address'];
    final family = <Map<String, dynamic>>[
      if (rawFamily is List)
        for (final entry in rawFamily)
          if (entry is Map) Map<String, dynamic>.from(entry),
    ];

    Map<String, dynamic> selectedPersonEntry = const <String, dynamic>{};
    if (family.isNotEmpty && targetPersonId.trim().isNotEmpty) {
      for (final entry in family) {
        if (_text(entry['id']) == targetPersonId) {
          selectedPersonEntry = entry;
          break;
        }
      }
    }
    if (selectedPersonEntry.isEmpty &&
        family.isNotEmpty &&
        rawName.isNotEmpty) {
      final rawLower = rawName.toLowerCase();
      for (final entry in family) {
        if (_text(entry['name']).toLowerCase() == rawLower) {
          selectedPersonEntry = entry;
          break;
        }
      }
    }

    final resolvedName = _text(selectedPersonEntry['name']).isNotEmpty
        ? _text(selectedPersonEntry['name'])
        : rawName;
    final resolvedLabel = _text(selectedPersonEntry['label']).isNotEmpty
        ? _text(selectedPersonEntry['label'])
        : rawLabel;
    final resolvedPhone = _text(selectedPersonEntry['phone']).isNotEmpty
        ? _text(selectedPersonEntry['phone'])
        : ((addressMeta['phone']?.toString().trim().isNotEmpty == true)
              ? addressMeta['phone'].toString().trim()
              : (addressMeta['phoneNumber']?.toString().trim().isNotEmpty ==
                    true)
              ? addressMeta['phoneNumber'].toString().trim()
              : (_text(sos['personPhone']).isNotEmpty)
              ? _text(sos['personPhone'])
              : (_text(sos['personContact']).isNotEmpty)
              ? _text(sos['personContact'])
              : '-');
    final resolvedAddress = _text(selectedPersonEntry['address']).isNotEmpty
        ? _text(selectedPersonEntry['address'])
        : (_text(sos['personAddress']).isNotEmpty
              ? _text(sos['personAddress'])
              : (_text(sos['address']).isNotEmpty
                    ? _text(sos['address'])
                    : (_text(user?['defaultAddress']).isNotEmpty
                          ? _text(user?['defaultAddress'])
                          : _text(user?['address']))));
    final photoUrl = _text(selectedPersonEntry['photoUrl']).isNotEmpty
        ? _text(selectedPersonEntry['photoUrl'])
        : _text(addressMeta['photoUrl']);

    return (
      name: resolvedName,
      label: resolvedLabel,
      address: resolvedAddress.trim().isNotEmpty
          ? resolvedAddress.trim()
          : 'Location not provided',
      phone: resolvedPhone.trim().isNotEmpty ? resolvedPhone.trim() : '-',
      photoUrl: photoUrl.trim().isNotEmpty ? photoUrl.trim() : null,
    );
  }

  Widget _buildCaregiverTab(Map<String, dynamic> sos) {
    final caregiverId = _text(sos['caregiverId']);
    final caregiverName = _text(sos['caregiverName']);
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);

    if (caregiverId.isEmpty && caregiverName.isEmpty) {
      return _buildUnavailablePlaceholder(
        message: 'Caregiver unavailable',
        explanation: 'This SOS does not have a caregiver assigned.',
        centerVertically: true,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef?.snapshots(),
      builder: (context, snap) {
        final caregiver = snap.data?.data() ?? const <String, dynamic>{};
        final name = _valueOrUnavailable(
          _text(caregiver['name']).isNotEmpty
              ? _text(caregiver['name'])
              : caregiverName,
        );
        final phone = _valueOrUnavailable(
          _text(caregiver['phone']).isNotEmpty
              ? _text(caregiver['phone'])
              : _text(caregiver['phoneNumber']),
        );
        final address = _valueOrUnavailable(
          _text(caregiver['defaultAddress']).isNotEmpty
              ? _text(caregiver['defaultAddress'])
              : (_text(caregiver['address']).isNotEmpty
                    ? _text(caregiver['address'])
                    : _text(caregiver['area'])),
        );
        final bioRaw = _text(caregiver['bio']);
        final prefs = extractServicePreferencesList(
          caregiver['servicePreferences'] ?? caregiver['services'],
        );
        final serviceFallback = _text(caregiver['service']);
        final service = prefs.isNotEmpty
            ? prefs.join(', ')
            : (serviceFallback.isNotEmpty
                  ? serviceFallback
                  : _valueOrUnavailable(_text(sos['service'])));
        final photoUrl = _text(caregiver['profile_photo']).isNotEmpty
            ? _text(caregiver['profile_photo'])
            : _text(caregiver['photoUrl']).isNotEmpty
            ? _text(caregiver['photoUrl'])
            : _text(caregiver['imageUrl']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Caregiver details'),
            const SizedBox(height: 4),
            _centerAvatar(name, photoUrl.isNotEmpty ? photoUrl : null),
            _buildTabContent([
              if (caregiverId.isNotEmpty)
                _buildInfoRow(
                  icon: Icons.badge_outlined,
                  title: 'Caregiver ID',
                  value: caregiverId,
                ),
              _buildInfoRow(
                icon: Icons.person,
                title: 'Caregiver name',
                value: name,
              ),
              _buildInfoRow(
                icon: Icons.medical_services_outlined,
                title: 'Services',
                value: service,
              ),
              _buildInfoRow(
                icon: Icons.phone_android,
                title: 'Contact',
                value: phone,
              ),
              _buildInfoRow(
                icon: Icons.home,
                title: 'Address',
                value: address,
                showBorder: bioRaw.trim().isNotEmpty,
              ),
              if (bioRaw.trim().isNotEmpty)
                _buildInfoContentRow(
                  icon: Icons.info_outline,
                  title: 'Bio',
                  value: bioRaw.trim(),
                ),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildClientTab(Map<String, dynamic> sos) {
    final userId = _text(sos['userId']);
    final userName = _text(sos['userName']);
    final userRef = userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(userId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef?.snapshots(),
      builder: (context, snap) {
        final user = snap.data?.data() ?? const <String, dynamic>{};
        final ownerName = _valueOrUnavailable(
          _text(user['name']).isNotEmpty ? _text(user['name']) : userName,
        );
        final ownerPhone = _valueOrUnavailable(
          _text(user['phone']).isNotEmpty
              ? _text(user['phone'])
              : _text(sos['userPhone']),
        );
        final ownerPhotoUrl = _text(user['profile_photo']).isNotEmpty
            ? _text(user['profile_photo'])
            : (_text(user['photoUrl']).isNotEmpty
                  ? _text(user['photoUrl'])
                  : _text(user['imageUrl']));

        final personDisplay = _resolvePersonDisplay(sos, user);
        final notes = _text(sos['personNotes']).isNotEmpty
            ? _text(sos['personNotes'])
            : _text(sos['notes']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Client details'),
            const SizedBox(height: 4),
            _centerAvatar(
              ownerName,
              ownerPhotoUrl.isNotEmpty ? ownerPhotoUrl : null,
            ),
            _buildTabContent([
              _buildInfoRow(
                icon: Icons.person,
                title: 'Client name',
                value: ownerName,
              ),
              _buildInfoRow(
                icon: Icons.phone_android,
                title: 'Client contact',
                value: ownerPhone,
              ),
              _buildInfoRow(
                icon: Icons.home,
                title: 'Care location',
                value: _valueOrUnavailable(personDisplay.address),
              ),
              _buildInfoRow(
                icon: Icons.accessibility_new_rounded,
                title: 'Primary person',
                value:
                    '${_valueOrUnavailable(personDisplay.name)} (${personDisplay.label.trim().isEmpty ? '—' : personDisplay.label.trim()})',
                showBorder: notes.trim().isNotEmpty,
              ),
              if (notes.trim().isNotEmpty)
                _buildInfoContentRow(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Notes',
                  value: notes.trim(),
                ),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildSosTab(Map<String, dynamic> sos) {
    final sosId = widget.sosId;
    final userId = _text(sos['userId']);
    final userNameHint = _text(sos['userName']);
    final userRef = userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(userId);

    final caregiverId = _text(sos['caregiverId']);
    final caregiverNameHint = _text(sos['caregiverName']);
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);

    final status = _valueOrUnavailable(_text(sos['status']));
    final createdAt = _timeLabel(sos['createdAt']);
    final reason = _valueOrUnavailable(_text(sos['reason']));
    final address = _valueOrUnavailable(_text(sos['address']));
    final bookingId = _text(sos['bookingId']);
    final service = _valueOrUnavailable(_text(sos['service']));
    final date = _text(sos['date']);
    final time = _text(sos['time']);
    final notes = _text(sos['personNotes']).isNotEmpty
        ? _text(sos['personNotes'])
        : _text(sos['notes']);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef?.snapshots(),
      builder: (context, userSnap) {
        final user = userSnap.data?.data();
        final ownerName = _valueOrUnavailable(
          _text(user?['name']).isNotEmpty ? _text(user?['name']) : userNameHint,
        );
        final ownerPhone = _valueOrUnavailable(
          _text(user?['phone']).isNotEmpty
              ? _text(user?['phone'])
              : _text(sos['userPhone']),
        );

        final personDisplay = _resolvePersonDisplay(sos, user);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: caregiverRef?.snapshots(),
          builder: (context, caregiverSnap) {
            final caregiver = caregiverSnap.data?.data();

            final caregiverName = _valueOrUnavailable(
              _text(caregiver?['name']).isNotEmpty
                  ? _text(caregiver?['name'])
                  : caregiverNameHint,
            );
            final caregiverPhotoUrl =
                _text(caregiver?['profile_photo']).isNotEmpty
                ? _text(caregiver?['profile_photo'])
                : (_text(caregiver?['photoUrl']).isNotEmpty
                      ? _text(caregiver?['photoUrl'])
                      : _text(caregiver?['imageUrl']));
            final caregiverPhone = _valueOrUnavailable(
              _text(caregiver?['phone']).isNotEmpty
                  ? _text(caregiver?['phone'])
                  : _text(caregiver?['phoneNumber']),
            );
            final caregiverAddress = _valueOrUnavailable(
              _text(caregiver?['defaultAddress']).isNotEmpty
                  ? _text(caregiver?['defaultAddress'])
                  : (_text(caregiver?['address']).isNotEmpty
                        ? _text(caregiver?['address'])
                        : _text(caregiver?['area'])),
            );
            final caregiverPrefs = extractServicePreferencesList(
              caregiver?['servicePreferences'] ?? caregiver?['services'],
            );
            final caregiverServiceFallback = _text(caregiver?['service']);
            final caregiverServicesValue = caregiverPrefs.isNotEmpty
                ? caregiverPrefs.join(', ')
                : (caregiverServiceFallback.trim().isNotEmpty
                      ? caregiverServiceFallback.trim()
                      : service);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(title: 'Caregiver'),
                const SizedBox(height: 4),
                _centerAvatar(
                  caregiverName.isNotEmpty ? caregiverName : 'Caregiver',
                  caregiverPhotoUrl.isNotEmpty ? caregiverPhotoUrl : null,
                ),
                _buildTabContent([
                  _buildInfoRow(
                    icon: Icons.person,
                    title: 'Caregiver name',
                    value: caregiverName,
                  ),
                  _buildInfoRow(
                    icon: Icons.medical_services_outlined,
                    title: 'Services',
                    value: caregiverServicesValue,
                  ),
                  _buildInfoRow(
                    icon: Icons.phone_android,
                    title: 'Contact',
                    value: caregiverPhone,
                  ),
                  _buildInfoRow(
                    icon: Icons.home,
                    title: 'Address',
                    value: caregiverAddress,
                    showBorder: false,
                  ),
                ]),
                const SizedBox(height: 14),
                _buildSectionHeader(title: 'Selected person'),
                const SizedBox(height: 4),
                _centerAvatar(
                  personDisplay.name.isNotEmpty
                      ? personDisplay.name
                      : 'Selected person',
                  personDisplay.photoUrl,
                ),
                _buildTabContent([
                  _buildInfoRow(
                    icon: Icons.person,
                    title: 'Name',
                    value: _valueOrUnavailable(personDisplay.name),
                  ),
                  _buildInfoRow(
                    icon: Icons.phone_android,
                    title: 'Contact',
                    value: _valueOrUnavailable(personDisplay.phone),
                  ),
                  _buildInfoRow(
                    icon: Icons.home,
                    title: 'Location',
                    value: _valueOrUnavailable(personDisplay.address),
                    showBorder: false,
                  ),
                ]),
                const SizedBox(height: 14),
                _buildSectionHeader(
                  title: 'SOS details',
                  hint: 'Live details pulled from the SOS record.',
                ),
                _buildTabContent([
                  _buildInfoRow(
                    icon: Icons.sos_outlined,
                    title: 'SOS ID',
                    value: sosId,
                  ),
                  _buildInfoRow(
                    icon: Icons.flag_outlined,
                    title: 'Status',
                    value: status,
                  ),
                  _buildInfoRow(
                    icon: Icons.access_time,
                    title: 'Created at',
                    value: createdAt,
                  ),
                  _buildInfoRow(
                    icon: Icons.report_outlined,
                    title: 'Reason',
                    value: reason,
                  ),
                  _buildInfoRow(
                    icon: Icons.home,
                    title: 'Address',
                    value: address,
                  ),
                  _buildInfoRow(
                    icon: Icons.medical_services_outlined,
                    title: 'Service',
                    value: service,
                  ),
                  if (date.trim().isNotEmpty)
                    _buildInfoRow(
                      icon: Icons.calendar_month,
                      title: 'Date',
                      value: date.trim(),
                    ),
                  if (time.trim().isNotEmpty)
                    _buildInfoRow(
                      icon: Icons.access_time,
                      title: 'Time',
                      value: time.trim(),
                    ),
                  _buildInfoRow(
                    icon: Icons.person,
                    title: 'Requested by',
                    value: ownerName,
                  ),
                  _buildInfoRow(
                    icon: Icons.phone_android,
                    title: 'Owner contact',
                    value: ownerPhone,
                    showBorder: notes.trim().isNotEmpty || bookingId.isNotEmpty,
                  ),
                  if (notes.trim().isNotEmpty)
                    _buildInfoContentRow(
                      icon: Icons.sticky_note_2_outlined,
                      title: 'Notes',
                      value: notes.trim(),
                    ),
                  if (bookingId.isNotEmpty)
                    _buildInfoContentRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'Booking ID',
                      value: bookingId,
                    ),
                ]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmergencyContactsTab(Map<String, dynamic> sos) {
    final userId = _text(sos['userId']);
    final userRef = userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(userId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef?.snapshots(),
      builder: (context, snap) {
        final user = snap.data?.data();
        final contacts = _extractEmergencyContacts(user);
        if (contacts.isEmpty) {
          return _buildUnavailablePlaceholder(
            message: 'Emergency contacts unavailable',
            explanation: 'Client has not added any emergency contacts yet.',
            centerVertically: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              title: 'Emergency contact',
              hint: 'Contacts provided by the client.',
            ),
            for (var i = 0; i < contacts.length; i++) ...[
              const SizedBox(height: 4),
              _centerAvatar(
                _text(contacts[i]['name']).isNotEmpty
                    ? _text(contacts[i]['name'])
                    : 'Emergency contact',
                _text(contacts[i]['photoUrl']).isNotEmpty
                    ? _text(contacts[i]['photoUrl'])
                    : null,
              ),
              _buildTabContent([
                _buildInfoRow(
                  icon: Icons.person,
                  title: 'Name',
                  value: _text(contacts[i]['name']).isNotEmpty
                      ? _text(contacts[i]['name'])
                      : 'Emergency contact',
                ),
                _buildInfoRow(
                  icon: Icons.family_restroom_rounded,
                  title: 'Relationship',
                  value: _text(contacts[i]['relationship']).isNotEmpty
                      ? _text(contacts[i]['relationship'])
                      : 'Relationship not set',
                ),
                Builder(
                  builder: (context) {
                    final phone = _text(contacts[i]['phone']);
                    return _buildInfoRow(
                      icon: Icons.phone_android,
                      title: 'Contact',
                      value: phone.isNotEmpty ? phone : 'Phone not available',
                      showBorder: false,
                    );
                  },
                ),
              ]),
              if (i != contacts.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  static const Color _bookingSummaryCardBorderStrong = Color(0xFFE1E4EA);
  static const Color _bookingSummaryCardShadow = Color(0x1A0B0C10);

  BoxDecoration _bookingSummaryCardDecoration({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _bookingSummaryCardBorderStrong),
      boxShadow: const [
        BoxShadow(
          color: _bookingSummaryCardShadow,
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  Widget _buildBookingSummaryTab(Map<String, dynamic> sos) {
    final bookingId = _text(sos['bookingId']);
    if (bookingId.isEmpty) {
      return _buildUnavailablePlaceholder(
        message: 'Booking summary unavailable',
        explanation: 'No booking is linked to this SOS record yet.',
        centerVertically: true,
      );
    }

    final bookingRef = FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: bookingRef.snapshots(),
      builder: (context, snap) {
        final booking = snap.data?.data();
        if (booking == null) {
          return _buildUnavailablePlaceholder(
            message: 'Booking summary unavailable',
            explanation: 'Unable to load the booking record.',
            centerVertically: true,
          );
        }
        return _buildBookingSummaryContent(booking);
      },
    );
  }

  Widget _buildBookingSummaryContent(Map<String, dynamic> booking) {
    final stageSnapshots = _extractStageSnapshots(booking);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            title: 'Stage photos',
            hint: 'Captured during the caregiver session.',
          ),
          if (stageSnapshots.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Text(
                'No stage photos available yet.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.62),
                  height: 1.25,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stageSnapshots.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.96,
                ),
                itemBuilder: (context, index) {
                  final entry = stageSnapshots[index];
                  final stageRaw = (entry['stage']?.toString() ?? '').trim();
                  final stageLabel = _formatStageSnapshotStage(stageRaw);
                  final ts = entry['createdAt'];
                  final dt = ts is Timestamp ? ts.toDate() : null;
                  final timeLabel = dt == null ? '-' : _formatSnapshotTime(dt);
                  final photoUrl = (entry['photoUrl']?.toString() ?? '').trim();

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: photoUrl.isEmpty
                        ? null
                        : () => _openStagePhotoPreview(
                            context,
                            photoUrl,
                            title: stageLabel,
                            subtitle: timeLabel,
                          ),
                    child: Container(
                      decoration: _bookingSummaryCardDecoration(radius: 16),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: photoUrl.isEmpty
                                ? Container(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    child: const Center(
                                      child: Icon(
                                        Icons.photo_outlined,
                                        color: Colors.black26,
                                        size: 26,
                                      ),
                                    ),
                                  )
                                : SafeNetworkImage(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    placeholder: const SizedBox.shrink(),
                                    errorWidget: Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.black26,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stageLabel,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: _profileDarkText,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  timeLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withValues(alpha: 0.6),
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractStageSnapshots(
    Map<String, dynamic> booking,
  ) {
    final raw = booking['stageSnapshots'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final entries = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final sorted = entries.toList(growable: true);
    sorted.sort((a, b) {
      final aTs = a['createdAt'];
      final bTs = b['createdAt'];
      final aDt = aTs is Timestamp ? aTs.toDate() : null;
      final bDt = bTs is Timestamp ? bTs.toDate() : null;
      if (aDt == null && bDt == null) return 0;
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return aDt.compareTo(bDt);
    });
    return sorted;
  }

  String _formatStageSnapshotStage(String raw) {
    final normalized = raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
    switch (normalized) {
      case 'START_SESSION':
        return 'Start session';
      case 'ARRIVED':
        return 'Arrived';
      case 'PROVIDE_SERVICES':
        return 'Provide services';
      case 'JOBS_DONE':
        return 'Jobs done';
      case 'COMPLETED':
        return 'Completed';
      default:
        if (normalized.isEmpty) return 'Stage';
        final words = normalized.split('_').where((w) => w.isNotEmpty).toList();
        if (words.isEmpty) return 'Stage';
        return words
            .map((w) => '${w[0]}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  String _formatSnapshotTime(DateTime dt) {
    return DateFormat('d MMM yyyy • h:mm a').format(dt);
  }

  Future<void> _openStagePhotoPreview(
    BuildContext context,
    String photoUrl, {
    String title = '',
    String subtitle = '',
  }) async {
    final safeUrl = photoUrl.trim();
    if (safeUrl.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.trim().isNotEmpty)
                        Text(
                          title.trim(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: _profileDarkText,
                          ),
                        ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AspectRatio(
                  aspectRatio: 1,
                  child: SafeNetworkImage(
                    safeUrl,
                    fit: BoxFit.cover,
                    placeholder: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: Container(
                      color: Colors.black.withValues(alpha: 0.04),
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.black38,
                          size: 28,
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
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sosRef = FirebaseFirestore.instance
        .collection('sos')
        .doc(widget.sosId);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        builder: (sheetContext, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: sosRef.snapshots(),
                builder: (context, snap) {
                  final sos = snap.data?.data() ?? const <String, dynamic>{};
                  Widget tabContent() {
                    final idx = _selectedTabIndex.clamp(0, labels.length - 1);
                    if (idx == 0) return _buildSosTab(sos);
                    if (idx == 1) return _buildBookingSummaryTab(sos);
                    if (idx == 2) return _buildCaregiverTab(sos);
                    if (idx == 3) return _buildClientTab(sos);
                    return _buildEmergencyContactsTab(sos);
                  }

                  return ListView(
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
                              'SOS details',
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
                      _buildOtherInfoTabs(),
                      tabContent(),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class AdminSosEditSheet extends StatefulWidget {
  const AdminSosEditSheet({super.key, required this.sosId});

  final String sosId;

  @override
  State<AdminSosEditSheet> createState() => _AdminSosEditSheetState();
}

class _AdminSosEditSheetState extends State<AdminSosEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sosIdCtrl = TextEditingController();
  late final TextEditingController _statusCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _selectedPersonCtrl;
  String _caregiverId = '';

  final LayerLink _statusFieldLink = LayerLink();
  final GlobalKey _statusFieldKey = GlobalKey();
  OverlayEntry? _statusOverlayEntry;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _sosIdCtrl.text = widget.sosId;
    _statusCtrl = TextEditingController();
    _reasonCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _selectedPersonCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _closeStatusMenu();
    _sosIdCtrl.dispose();
    _statusCtrl.dispose();
    _reasonCtrl.dispose();
    _addressCtrl.dispose();
    _selectedPersonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      _caregiverId = _text(data['caregiverId']);
      _statusCtrl.text = _text(data['status']).isNotEmpty
          ? _text(data['status'])
          : 'ACTIVE';
      _reasonCtrl.text = _text(data['reason']);
      _addressCtrl.text = _text(data['address']);
      _selectedPersonCtrl.text = _text(data['selectedPersonName']);
    } catch (_) {
      _statusCtrl.text = 'ACTIVE';
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _toggleStatusMenu() {
    if (_statusOverlayEntry == null) {
      _openStatusMenu();
    } else {
      _closeStatusMenu();
    }
  }

  void _openStatusMenu() {
    _closeStatusMenu();
    final overlay = Overlay.of(context);
    final box =
        _statusFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    const options = <String>['ACTIVE', 'RESOLVED'];

    _statusOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeStatusMenu,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _statusFieldLink,
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: options
                              .map(
                                (option) => InkWell(
                                  onTap: () => _selectStatus(option),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: _accentGold,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            option,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
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
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_statusOverlayEntry!);
  }

  void _closeStatusMenu() {
    _statusOverlayEntry?.remove();
    _statusOverlayEntry = null;
  }

  void _selectStatus(String value) {
    setState(() => _statusCtrl.text = value);
    _closeStatusMenu();
  }

  Future<void> _save() async {
    if (_saving) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('sos')
          .doc(widget.sosId)
          .update({
            'status': _statusCtrl.text.trim(),
            'reason': _reasonCtrl.text.trim(),
            'selectedPersonName': _selectedPersonCtrl.text.trim(),
            'address': _addressCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final caregiverRef = _caregiverId.trim().isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('caregivers')
              .doc(_caregiverId.trim());

    InputDecoration inputDecoration({
      required String labelText,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.55),
        ),
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
        suffixIcon: suffixIcon,
      );
    }

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
                          'Edit SOS',
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
                  if (!_loaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: caregiverRef?.get(),
                      builder: (context, snapshot) {
                        final caregiverData = snapshot.data?.data();
                        final caregiverName =
                            (caregiverData?['name'] as String?)?.trim() ??
                            _caregiverId.trim();
                        final caregiverPhoto =
                            (caregiverData?['profile_photo'] as String?)
                                ?.trim() ??
                            (caregiverData?['photoUrl'] as String?)?.trim();

                        final displayName = caregiverName.isNotEmpty
                            ? caregiverName
                            : 'Caregiver';

                        return Column(
                          children: [
                            DefaultProfileAvatar(
                              radius: 34,
                              photoUrl: caregiverPhoto?.isNotEmpty == true
                                  ? caregiverPhoto
                                  : null,
                              label: displayName.isNotEmpty ? displayName : '?',
                            ),
                            const SizedBox(height: 10),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: _profileDarkText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_caregiverId.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _caregiverId.trim(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _sosIdCtrl,
                      readOnly: true,
                      showCursor: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: inputDecoration(labelText: 'SOS ID'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'SOS details',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: _profileDarkText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    CompositedTransformTarget(
                      link: _statusFieldLink,
                      child: TextFormField(
                        key: _statusFieldKey,
                        controller: _statusCtrl,
                        readOnly: true,
                        showCursor: false,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _profileDarkText,
                        ),
                        decoration: inputDecoration(
                          labelText: 'Status',
                          suffixIcon: const Icon(Icons.expand_more, size: 18),
                        ),
                        onTap: _toggleStatusMenu,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          return value.isEmpty ? 'Required' : null;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _reasonCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: inputDecoration(labelText: 'Reason'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _selectedPersonCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: inputDecoration(labelText: 'Selected person'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addressCtrl,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: inputDecoration(labelText: 'Address'),
                      maxLines: 4,
                    ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
