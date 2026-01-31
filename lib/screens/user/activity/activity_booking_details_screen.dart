import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../widgets/standard_app_bar.dart';
import 'activity_tracking_helpers.dart';
import '../../../utils/phone_caller.dart';
import '../../../utils/service_preferences.dart';
import 'track_caregiver_screen.dart';
import '../booking/booking_person_screen.dart';
import '../booking/booking_summary_screen.dart';
import '../user_root_screen.dart';
import '../../../models/caregiver_model.dart';
import '../../../widgets/schedule_booking_telegram_sheet.dart';

const Color _cardBorder = Color(0xFFEBEDF0);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _accentBlue = _accentGreen; // Match Home screen blue.
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _screenBackground = Color(0xFFF7F8FA);
const Color _cardShadow = Color(0x1A0B0C10);
const Color _cardBorderStrong = Color(0xFFE1E4EA);
const double _cardRadius = 18;
const Color _mutedText = Color(0xFF6B7280);
const Color _accentGold = Color(0xFFF4B63D);
const Color _avatarOutlineColor = Colors.white;

BoxDecoration _premiumCardDecoration({double radius = _cardRadius}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _cardBorderStrong),
    boxShadow: const [
      BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
    ],
  );
}

const TextStyle _sectionHeaderTextStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _profileDarkText,
  letterSpacing: -0.15,
);

const TextStyle _fieldLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: _mutedText,
);

const TextStyle _fieldValueTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: _profileDarkText,
  height: 1.25,
);
const String _defaultAvatarUrl =
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';

class _EmergencyAlertError implements Exception {
  const _EmergencyAlertError({required this.message});

  final String message;
}

class _TimeRange {
  const _TimeRange({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class _EmergencyAlertBottomSheet extends StatefulWidget {
  const _EmergencyAlertBottomSheet({
    required this.contacts,
    required this.onSubmit,
    required this.onCompleted,
  });

  final List<Map<String, dynamic>> contacts;
  final Future<void> Function(Set<String> selectedIds, String reason) onSubmit;
  final VoidCallback onCompleted;

  @override
  State<_EmergencyAlertBottomSheet> createState() =>
      _EmergencyAlertBottomSheetState();
}

class _EmergencyAlertBottomSheetState
    extends State<_EmergencyAlertBottomSheet> {
  final TextEditingController _reasonController = TextEditingController();
  late Set<String> _selectedIds;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{
      for (final c in widget.contacts)
        if ((c['id']?.toString().trim() ?? '').isNotEmpty)
          c['id'].toString().trim(),
    };
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _contactName(Map<String, dynamic> c) {
    final raw = c['name']?.toString().trim() ?? '';
    return raw.isNotEmpty ? raw : 'Emergency contact';
  }

  String _contactMeta(Map<String, dynamic> c) {
    final label =
        c['relationship']?.toString().trim() ??
        c['label']?.toString().trim() ??
        '';
    final phone =
        c['phone']?.toString().trim() ?? c['contact']?.toString().trim() ?? '';
    return [
      if (label.isNotEmpty) label,
      if (phone.isNotEmpty) phone,
    ].join(' • ');
  }

  String _contactId(Map<String, dynamic> c) => c['id']?.toString().trim() ?? '';

  Future<void> _submit() async {
    if (_submitting) return;
    if (_selectedIds.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_selectedIds, _reasonController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCompleted();
    } on _EmergencyAlertError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg != null && msg.isNotEmpty
                ? msg
                : 'Unable to start emergency alert.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start emergency alert.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _contactRow(Map<String, dynamic> contact) {
    final id = _contactId(contact);
    final selected = id.isNotEmpty && _selectedIds.contains(id);
    return InkWell(
      onTap: (id.isEmpty || _submitting)
          ? null
          : () {
              setState(() {
                if (selected) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              });
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.red.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? Colors.red : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selected
                      ? Colors.red
                      : Colors.black.withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _contactName(contact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _contactMeta(contact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.86;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Emergency alert',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: Colors.black.withValues(alpha: 0.7),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: ScrollConfiguration(
                    behavior: const _NoOverscrollScrollBehavior(),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      physics: const ClampingScrollPhysics(),
                      children: [
                        Text(
                          'Select who to notify',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (widget.contacts.isEmpty)
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              'No emergency contacts available.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.62),
                              ),
                            ),
                          )
                        else ...[
                          for (var i = 0; i < widget.contacts.length; i++) ...[
                            _contactRow(widget.contacts[i]),
                            if (i != widget.contacts.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Reason',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _reasonController,
                          minLines: 2,
                          maxLines: 4,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _profileDarkText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'What happened?',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.38),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.03),
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              12,
                              12,
                              12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ElevatedButton(
                    onPressed:
                        (_submitting ||
                            widget.contacts.isEmpty ||
                            _selectedIds.isEmpty)
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Start emergency alert'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityBookingDetailsScreen extends StatefulWidget {
  const ActivityBookingDetailsScreen({
    super.key,
    required this.bookingId,
    this.hideBookingDetailsTab = false,
    this.caregiverId,
    this.person,
    this.selectedAddress,
    this.initialTabIndex = 0,
    this.showTrackFrontSheet = false,
    this.showPreviewFrontSheet = true,
    this.caregiverView = false,
  });

  final String bookingId;
  final bool hideBookingDetailsTab;
  final String? caregiverId;
  final PersonProfile? person;
  final AddressItem? selectedAddress;
  final int initialTabIndex;
  final bool showTrackFrontSheet;
  final bool showPreviewFrontSheet;
  final bool caregiverView;

  @override
  State<ActivityBookingDetailsScreen> createState() =>
      _ActivityBookingDetailsScreenState();
}

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _ActivityBookingDetailsScreenState
    extends State<ActivityBookingDetailsScreen>
    with TickerProviderStateMixin {
  static const double _sheetMaxExtentRaw = 1.0;
  static const double _sheetFallbackInitialExtentRaw = 0.62;
  static const double _sheetDefaultMinExtentRaw = 0.42;
  static const double _sheetDefaultMaxInitialExtentRaw = 0.74;

  bool _isLoading = true;
  String? _error;
  bool _notFound = false;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _caregiverData;
  Map<String, dynamic>? _userData;
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final AnimationController _tabEntryController;
  late final Animation<double> _tabFade;
  late final Animation<Offset> _tabSlide;
  int _selectedTabIndex = 0;
  int? _selectedRatingFilter;
  DateTime? _scheduleSelectedDay;
  final Map<String, List<_TimeRange>> _scheduleTakenCache =
      <String, List<_TimeRange>>{};
  final Set<String> _scheduleLoadingTaken = <String>{};
  final GlobalKey _metricsKey = GlobalKey();
  double? _autoInitialSheetExtent;
  final Map<String, Future<_UserMini>> _reviewUserCache =
      <String, Future<_UserMini>>{};
  bool get _isPreviewMode => widget.bookingId.trim().isEmpty;
  bool get _canBookFromSchedule =>
      _isPreviewMode &&
      (widget.caregiverId?.trim().isNotEmpty == true) &&
      widget.person != null &&
      widget.selectedAddress != null;
  bool _showTrackButton = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bookingStatusSub;
  String? _lastLiveBookingStatus;
  bool _completionPopupShown = false;
  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;
  double _panelMinExtent = 0.0;
  double _panelMaxExtent = 1.0;

  // ignore: unused_element
  void _callEmergencyContact(BuildContext context, String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    try {
      await callNumber(trimmed);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to place the call.')),
      );
    }
  }

  List<Map<String, dynamic>> _addressEntries(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['address'] ?? data['addresses'] ?? data['addressList'];
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }
    if (raw is Iterable) {
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic>? _primaryAddressMap(Map<String, dynamic>? data) {
    final entries = _addressEntries(data);
    if (entries.isEmpty) return null;
    final defaultEntry = entries.firstWhere(
      (entry) => entry['isDefault'] == true,
      orElse: () => entries.first,
    );
    return defaultEntry;
  }

  Map<String, dynamic>? _addressEntryForPerson({
    required Map<String, dynamic>? userData,
    required String personId,
    required String bookingId,
    required String addressId,
  }) {
    final entries = _addressEntries(userData);
    if (addressId.trim().isNotEmpty) {
      for (final entry in entries) {
        final entryId = entry['id']?.toString();
        if (entryId != null && entryId == addressId.trim()) {
          return entry;
        }
      }
    }
    if (personId.trim().isNotEmpty) {
      for (final entry in entries) {
        final entryId = entry['id']?.toString();
        if (entryId != null && entryId == personId.trim()) {
          return entry;
        }
      }
    } else if (bookingId.trim().isNotEmpty) {
      for (final entry in entries) {
        final entryBookingId = entry['bookingId']?.toString();
        if (entryBookingId != null && entryBookingId == bookingId.trim()) {
          return entry;
        }
      }
    }
    return null;
  }

  String? _stringValue(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Iterable) {
      final joinable = value.whereType<String>().toList();
      if (joinable.isNotEmpty) return joinable.join(', ');
    }
    if (value != null) return value.toString();
    return null;
  }

  ({String name, String label, String address, String phone, String? photoUrl})
  _resolvePersonDisplay(Map<String, dynamic> booking) {
    final userData = _userData;
    final personId = normalizeString(booking['personId']) ?? '';
    final addressId = normalizeString(booking['addressId']) ?? '';
    final selectedEntry =
        _addressEntryForPerson(
          userData: userData,
          personId: personId,
          bookingId: widget.bookingId,
          addressId: addressId,
        ) ??
        _primaryAddressMap(userData);

    final rawName =
        _stringValue(selectedEntry?['name']) ??
        normalizeString(booking['personName']) ??
        'Selected person';
    final rawLabel =
        _stringValue(selectedEntry?['label']) ??
        _stringValue(selectedEntry?['forWho']) ??
        normalizeString(booking['personLabel']) ??
        'Care recipient';
    final rawPhone =
        _stringValue(selectedEntry?['phone']) ??
        normalizeString(booking['personPhone']) ??
        normalizeString(booking['phone']) ??
        '-';
    final addressText =
        _stringValue(
          selectedEntry?['address'] ??
              selectedEntry?['addressLine'] ??
              selectedEntry?['location'] ??
              selectedEntry?['street'],
        ) ??
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['address']) ??
        normalizeString(_userData?['defaultAddress']) ??
        'Location not provided';
    final photoUrl =
        normalizeString(selectedEntry?['photoUrl']) ??
        normalizeString(booking['personPhotoUrl']) ??
        normalizeString(booking['personPhoto']);

    return (
      name: rawName,
      label: rawLabel,
      address: addressText,
      phone: rawPhone,
      photoUrl: (photoUrl?.trim().isNotEmpty == true) ? photoUrl!.trim() : null,
    );
  }

  Widget _previewCalendarButton() {
    return Container(
      height: 48,
      width: 48,
      decoration: const BoxDecoration(
        color: _accentGold,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        tooltip: 'Schedule',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: const Icon(
          Icons.calendar_today_rounded,
          size: 18,
          color: Colors.black,
        ),
        splashRadius: 24,
        onPressed: _bookInAdvance,
      ),
    );
  }

  Widget _trackFrontSheet({
    required String caregiverName,
    required String? caregiverPhotoUrl,
    required String serviceLabel,
    String? metaLine,
  }) {
    final name = caregiverName.trim().isNotEmpty
        ? caregiverName.trim()
        : 'Caregiver';
    final subtitleBase = serviceLabel.trim().isNotEmpty
        ? serviceLabel.trim()
        : 'Caregiver assigned';
    final subtitle = (metaLine != null && metaLine.trim().isNotEmpty)
        ? '$subtitleBase • ${metaLine.trim()}'
        : subtitleBase;

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _avatarOutlineColor, width: 2.2),
                  ),
                  child: DefaultProfileAvatar(
                    radius: 22,
                    photoUrl: caregiverPhotoUrl,
                    label: name,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _openTracker,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGold,
                        foregroundColor: const Color.fromARGB(255, 20, 20, 20),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Track caregiver'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewFrontSheet() {
    final person = widget.person;
    final selectedAddress = widget.selectedAddress;
    if (person == null || selectedAddress == null) {
      return const SizedBox.shrink();
    }

    final name = person.name.trim().isNotEmpty ? person.name.trim() : 'Person';
    final labelFallback = person.label?.trim() ?? '';
    final addressLabel = selectedAddress.label?.trim().isNotEmpty == true
        ? selectedAddress.label!.trim()
        : labelFallback;
    final baseSubtitle = person.address.trim().isNotEmpty
        ? person.address.trim()
        : 'Care location';
    final trimmedAddressLine =
        selectedAddress.addressLine?.trim().isNotEmpty == true
        ? selectedAddress.addressLine!.trim()
        : (selectedAddress.subtitle.trim().isNotEmpty
              ? selectedAddress.subtitle.trim()
              : baseSubtitle);
    final frontSubtitle = addressLabel.isNotEmpty
        ? '$addressLabel • $trimmedAddressLine'
        : (trimmedAddressLine.isNotEmpty ? trimmedAddressLine : baseSubtitle);

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _avatarOutlineColor, width: 2.2),
                  ),
                  child: DefaultProfileAvatar(
                    radius: 22,
                    photoUrl: person.photoUrl,
                    label: name,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        frontSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _previewCalendarButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _bookCaregiverNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGold,
                        foregroundColor: const Color.fromARGB(255, 20, 20, 20),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Book caregiver'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
    _panelController =
        AnimationController(
          vsync: this,
          value: 0.0,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (!mounted) return;
          setState(() {});
        });
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );
    _tabEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tabFade = CurvedAnimation(
      parent: _tabEntryController,
      curve: Curves.easeOutCubic,
    );
    _tabSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _tabEntryController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fetchBooking();
    _startBookingStatusListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward(from: 0);
      _tabEntryController.value = 1;
    });
  }

  String _normalizeBookingStatusForListener(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
  }

  void _startBookingStatusListener() {
    if (widget.caregiverView) return;
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) return;
    _bookingStatusSub?.cancel();
    _bookingStatusSub = FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .listen((snap) {
          final data = snap.data();
          final next = _normalizeBookingStatusForListener(
            normalizeString(data?['status']) ?? '',
          );
          final prev = _lastLiveBookingStatus;
          _lastLiveBookingStatus = next;
          if (prev == null || prev == next) return;
          if (next != 'COMPLETED') return;
          if (_completionPopupShown) return;
          _completionPopupShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showCompletionPopupAndRedirect();
          });
        });
  }

  Future<void> _showCompletionPopupAndRedirect() async {
    if (!mounted) return;
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _accentGold.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _accentGold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.black87,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Booking completed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your booking has been completed. Redirecting to your history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: const Text('View history'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() => dialogOpen = false);

    unawaited(dialogFuture);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted && dialogOpen) {
      Navigator.of(context).pop();
    }
    await dialogFuture;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const UserRootScreen(
          initialIndex: 3,
          activityInitialCategoryIndex: 2,
        ),
      ),
      (_) => false,
    );
  }

  void _selectTab(int index) {
    if (_selectedTabIndex == index) return;
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final hasBookingTab = !_isPreviewMode && !widget.hideBookingDetailsTab;
    final showScheduleTab = _isPreviewMode && !widget.caregiverView;
    final scheduleIndex = showScheduleTab ? (hasBookingTab ? 2 : 1) : -1;
    setState(() {
      _selectedTabIndex = index;
      if (scheduleIndex >= 0 && index == scheduleIndex) {
        _scheduleSelectedDay = normalizedToday;
      }
    });
    _tabEntryController.forward(from: 0);
  }

  void _scheduleAutoSheetExtentUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final metricsContext = _metricsKey.currentContext;
      if (metricsContext == null) return;
      final renderObject = metricsContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final metricsBottom =
          renderObject.localToGlobal(Offset.zero).dy + renderObject.size.height;
      final screenHeight = MediaQuery.of(context).size.height;
      if (screenHeight <= 0) return;

      const gapBelowMetrics = 12.0;
      final desiredTop = metricsBottom + gapBelowMetrics;
      final initial = (1 - (desiredTop / screenHeight)).clamp(0.0, 1.0);

      if (_autoInitialSheetExtent != null &&
          (_autoInitialSheetExtent! - initial).abs() < 0.01) {
        return;
      }
      setState(() => _autoInitialSheetExtent = initial);
    });
  }

  void _onPanelHandleDragUpdate(double delta, double rangePx) {
    if (rangePx <= 0) return;
    _panelUserInteracted = true;
    final next = (_panelController.value - (delta / rangePx))
        .clamp(0.0, 1.0)
        .toDouble();
    _panelController.value = next;
  }

  void _onPanelHandleDragEnd(double velocityPxPerSecond) {
    const flingVelocityThreshold = 520.0;
    if ((_panelMaxExtent - _panelMinExtent).abs() < 0.001) return;
    _panelUserInteracted = true;
    final current = _panelController.value;
    final bool shouldExpand;
    if (velocityPxPerSecond.abs() > flingVelocityThreshold) {
      shouldExpand = velocityPxPerSecond < 0;
    } else {
      shouldExpand = current >= 0.5;
    }
    _panelController.animateTo(
      shouldExpand ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _bookingStatusSub?.cancel();
    _entryController.dispose();
    _tabEntryController.dispose();
    _panelController.dispose();
    _panelScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in to view booking details.';
        _isLoading = false;
      });
      return;
    }

    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) {
      final caregiverId = widget.caregiverId?.trim() ?? '';
      if (caregiverId.isNotEmpty) {
        await _loadCaregiver(caregiverId);
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();
      if (!doc.exists) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
        return;
      }
      final data = doc.data();
      final caregiverId = (data?['caregiverId'] as String?) ?? '';
      setState(() {
        _booking = data;
        _isLoading = false;
      });
      if (caregiverId.isNotEmpty) {
        _loadCaregiver(caregiverId);
      }
      final userId = (data?['userId'] as String?) ?? '';
      if (userId.isNotEmpty) {
        _loadUser(userId);
      }

      _computeTrackButtonVisibility(data);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _computeTrackButtonVisibility(Map<String, dynamic>? booking) {
    final status = normalizeString(booking?['status'])?.toUpperCase() ?? '';
    final normalized = status.trim().toUpperCase();
    final isTerminal =
        normalized == 'COMPLETED' ||
        normalized == 'SCHEDULED' ||
        normalized == 'PENDING' ||
        normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized.startsWith('CANCEL');
    if (!mounted) return;
    setState(() => _showTrackButton = !isTerminal);
  }

  Future<void> _loadCaregiver(String caregiverId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .get();
      final data = doc.data();
      if (data == null) return;
      if (!mounted) return;
      setState(() {
        _caregiverData = data;
      });
    } catch (_) {}
  }

  Future<void> _loadUser(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = doc.data();
      if (data == null) return;
      if (!mounted) return;
      setState(() {
        _userData = data;
      });
    } catch (_) {}
  }

  String _formatDate(String raw) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(raw);
      return DateFormat('EEEE, d MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatTime(String raw) {
    try {
      final t = DateFormat('HH:mm').parseLoose(raw);
      return DateFormat('h:mm a').format(t);
    } catch (_) {
      return raw;
    }
  }

  TimeOfDay? _parseStoredTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final hhmm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
    if (hhmm != null) {
      final h = int.tryParse(hhmm.group(1)!);
      final m = int.tryParse(hhmm.group(2)!);
      if (h == null || m == null) return null;
      if (h < 0 || h > 23 || m < 0 || m > 59) return null;
      return TimeOfDay(hour: h, minute: m);
    }
    try {
      final t = DateFormat('HH:mm').parseLoose(trimmed);
      return TimeOfDay(hour: t.hour, minute: t.minute);
    } catch (_) {
      try {
        var normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
        normalized = normalized.replaceAllMapped(
          RegExp(r'^(\d{1,2}:\d{2})(am|pm)$', caseSensitive: false),
          (m) => '${m.group(1)} ${m.group(2)}',
        );
        normalized = normalized.toUpperCase();
        final t = DateFormat('h:mm a').parseLoose(normalized);
        return TimeOfDay(hour: t.hour, minute: t.minute);
      } catch (_) {
        return null;
      }
    }
  }

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  Future<List<_TimeRange>> _fetchTakenRanges({
    required String caregiverId,
    required DateTime day,
    required String? excludeBookingId,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final ymd = _ymd(day);

      // Fetch by caregiverId only to avoid composite-index failures, then filter
      // locally for the selected day + active statuses.
      final snap = await db
          .collection('bookings')
          .where('caregiverId', isEqualTo: caregiverId)
          .get();
      final docs = snap.docs.toList(growable: false);

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
      };

      bool matchesDay(dynamic value) {
        if (value == null) return false;
        if (value is Timestamp) {
          final dt = value.toDate();
          return _ymd(dt) == ymd;
        }
        final raw = value.toString().trim();
        if (raw.isEmpty) return false;
        return raw == ymd;
      }

      final seen = <String>{};
      final ranges = <_TimeRange>[];
      for (final doc in docs) {
        if (!seen.add(doc.id)) continue;
        if (excludeBookingId != null && doc.id == excludeBookingId) continue;
        final data = doc.data();
        final statusRaw = data['status']?.toString().trim() ?? '';
        final status = statusRaw.toUpperCase();
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
        if (eMin <= sMin) {
          end = _endTimeFromStart(start);
        }
        ranges.add(_TimeRange(start: start, end: end));
      }
      ranges.sort((a, b) {
        final aMin = a.start.hour * 60 + a.start.minute;
        final bMin = b.start.hour * 60 + b.start.minute;
        return aMin.compareTo(bMin);
      });
      return ranges;
    } catch (_) {
      return const <_TimeRange>[];
    }
  }

  TimeOfDay _endTimeFromStart(TimeOfDay startTime) {
    final totalMinutes = (startTime.hour * 60) + startTime.minute + 120;
    final clamped = totalMinutes.clamp(0, 24 * 60 - 1);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  Future<void> _goToBookingSummary({
    required String caregiverId,
    required DateTime scheduleDate,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required bool showScheduleSection,
  }) async {
    final person = widget.person;
    final selectedAddress = widget.selectedAddress;
    if (person == null || selectedAddress == null) return;
    final caregiver = CaregiverModel.safeFromMap(caregiverId, _caregiverData);
    final price = _safeDouble(caregiver.price, 1.0);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingSummaryScreen(
          person: person,
          caregiver: caregiver,
          scheduleDate: scheduleDate,
          startTime: startTime,
          endTime: endTime,
          price: price,
          selectedAddress: selectedAddress,
          showScheduleSection: showScheduleSection,
        ),
      ),
    );
  }

  Future<void> _bookCaregiverNow() async {
    final caregiverId = widget.caregiverId?.trim() ?? '';
    if (caregiverId.isEmpty) return;
    final now = DateTime.now();
    final start = TimeOfDay.fromDateTime(now);
    final end = _endTimeFromStart(start);
    await _goToBookingSummary(
      caregiverId: caregiverId,
      scheduleDate: now,
      startTime: start,
      endTime: end,
      showScheduleSection: false,
    );
  }

  Future<void> _bookInAdvance() async {
    final caregiverId = widget.caregiverId?.trim() ?? '';
    if (caregiverId.isEmpty) return;
    final now = DateTime.now();
    final initialDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final result = await showScheduleBookingTelegramSheet(
      context: context,
      caregiverId: caregiverId,
      initialDay: initialDay,
      initialStart: const TimeOfDay(hour: 8, minute: 0),
      initialEnd: const TimeOfDay(hour: 10, minute: 0),
      primaryColor: _accentGold,
      excludeBookingId: null,
      allowInitialDayEvenIfUnavailable: false,
      enableDrag: false,
      barrierColor: Colors.black.withValues(alpha: 0.54),
    );
    if (!mounted || result == null) return;
    await _goToBookingSummary(
      caregiverId: caregiverId,
      scheduleDate: result.day,
      startTime: result.start,
      endTime: result.end,
      showScheduleSection: true,
    );
  }

  Future<void> _openTracker() async {
    final booking = _booking;
    if (booking == null) return;
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) return;
    final personId = normalizeString(booking['personId']) ?? '';
    final caregiverId = normalizeString(booking['caregiverId']) ?? '';
    if (caregiverId.isEmpty) return;
    final caregiverName =
        normalizeString(booking['caregiverName']) ??
        normalizeString(_caregiverData?['name']) ??
        'Caregiver';

    await FirebaseFirestore.instance.collection('bookings').doc(bookingId).set({
      'trackingCaregiverId': caregiverId,
      if (personId.isNotEmpty) 'trackingPersonId': personId,
      'trackingUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackCaregiverScreen(
          bookingId: bookingId,
          caregiverName: caregiverName,
          caregiverId: caregiverId,
          personId: personId.isNotEmpty ? personId : null,
          showStatusUpdateButton: false,
        ),
      ),
    );
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
        final name = (data['name'] as String?)?.trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        return _UserMini(
          name: (name?.isNotEmpty == true) ? name! : fallbackName,
          photoUrl: (photoUrl?.isNotEmpty == true) ? photoUrl! : null,
        );
      } catch (_) {
        return _UserMini(name: fallbackName, photoUrl: null);
      }
    });
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
          border: Border.all(color: _avatarOutlineColor, width: 2.2),
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
        border: Border.all(color: _avatarOutlineColor, width: 2.2),
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

  Widget _starRow(double rating, {double size = 16}) {
    final clamped = rating.clamp(0.0, 5.0);
    final full = clamped.floor();
    final half = (clamped - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;
    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star_rounded, size: size, color: _accentGold));
    }
    if (half == 1) {
      stars.add(Icon(Icons.star_half_rounded, size: size, color: _accentGold));
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
                valueColor: const AlwaysStoppedAnimation<Color>(_accentGold),
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
      var rest = trimmed.substring(firstToken.length).trim();
      if (rest.startsWith('ƒ~.')) rest = rest.substring(1).trim();
      if (rest.startsWith('aŸY.')) rest = rest.substring(2).trim();
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rating.toString()),
          const SizedBox(width: 4),
          const Icon(Icons.star_rounded, size: 14, color: _accentGold),
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
                ? _accentGold.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        backgroundColor: selected ? _accentGold : Colors.white,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
      child: content,
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
                  border: Border.all(color: _avatarOutlineColor, width: 2),
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

  Widget _buildHeroCover(String photoUrl) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: SafeNetworkImage(
              photoUrl,
              fit: BoxFit.cover,
              placeholder: Container(
                color: Colors.grey[200],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: Container(color: Colors.grey[200]),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
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

  Widget _buildHeaderCard({
    required String name,
    required String serviceLabel,
    required List<String> servicePreferences,
    required String defaultAddress,
    required int clientsCount,
    required int verifiedDocsCount,
    required int reviewsCount,
    String? photoUrl,
    Widget? footer,
    bool hideMetrics = false,
    bool showServiceSubtitle = false,
  }) {
    const avatarRadius = 38.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 44, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: _cardBorderStrong, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: _cardShadow,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                  letterSpacing: -0.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (showServiceSubtitle && serviceLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  serviceLabel.trim(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.62),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      defaultAddress,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.65),
                        height: 1.25,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              if (!hideMetrics) ...[
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                const SizedBox(height: 10),
                footer ??
                    Row(
                      children: [
                        _buildMetricItem(
                          icon: Icons.groups_2_outlined,
                          label: 'Clients',
                          value: clientsCount.toString(),
                        ),
                        _buildMetricItem(
                          icon: Icons.verified_outlined,
                          label: 'Certification',
                          value: verifiedDocsCount.toString(),
                        ),
                        _buildMetricItem(
                          icon: Icons.star_rounded,
                          label: 'Reviews',
                          value: reviewsCount.toString(),
                        ),
                      ],
                    ),
              ],
            ],
          ),
        ),
        Positioned(
          top: -(avatarRadius),
          left: 0,
          right: 0,
          child: Center(
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
                radius: avatarRadius,
                photoUrl: photoUrl,
                label: name,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 118;
          final iconBox = isTight ? 40.0 : 46.0;
          final iconSize = isTight ? 20.0 : 22.0;
          final gap = isTight ? 7.0 : 10.0;
          final valueFontSize = isTight ? 13.0 : 14.0;
          final labelFontSize = isTight ? 10.5 : 11.0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentBlue.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _accentBlue.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: iconSize, color: _accentBlue),
              ),
              SizedBox(width: gap),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.w800,
                        color: _profileDarkText,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                        color: _mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderPill({required IconData icon, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black.withValues(alpha: 0.62)),
          const SizedBox(width: 6),
          Text(
            trimmed,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricsRow({
    required int clientsCount,
    required int verifiedDocsCount,
    required int reviewsCount,
  }) {
    return Padding(
      // Push this down so it doesn't overlap the floating header card.
      padding: const EdgeInsets.fromLTRB(16, 74, 16, 10),
      child: Row(
        children: [
          _buildMetricItem(
            icon: Icons.groups_2_outlined,
            label: 'Clients',
            value: clientsCount.toString(),
          ),
          _buildMetricItem(
            icon: Icons.verified_outlined,
            label: 'Certification',
            value: verifiedDocsCount.toString(),
          ),
          _buildMetricItem(
            icon: Icons.star_rounded,
            label: 'Reviews',
            value: reviewsCount.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherInfoTabs({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
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
            const Icon(Icons.bolt_rounded, size: 32, color: _accentBlue),
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

    return Builder(
      builder: (context) {
        final height = (MediaQuery.sizeOf(context).height * 0.35).clamp(
          260.0,
          420.0,
        );
        return SizedBox(height: height, child: centered);
      },
    );
  }

  Widget _buildCaregiverDetailsTab({
    required Map<String, dynamic>? caregiver,
    required Stream<QuerySnapshot<Map<String, dynamic>>> documentsStream,
  }) {
    final caregiverName = normalizeString(caregiver?['name']) ?? 'Caregiver';
    final caregiverPhotoUrl =
        (normalizeString(caregiver?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(caregiver?['photoUrl'])!.trim()
        : (normalizeString(caregiver?['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(caregiver?['imageUrl'])!.trim()
              : null));
    final caregiverLocation =
        normalizeString(caregiver?['defaultAddress']) ??
        normalizeString(caregiver?['address']) ??
        normalizeString(caregiver?['area']) ??
        'Location not provided';

    final bioRaw = (caregiver?['bio'] as String?)?.trim() ?? '';
    final prefs = extractServicePreferencesList(
      caregiver?['servicePreferences'] ?? caregiver?['services'],
    );
    final fallbackServiceLabel = normalizeString(caregiver?['service']) ?? '';
    final services = prefs
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final servicesList = services.isNotEmpty
        ? services
        : (fallbackServiceLabel.trim().isNotEmpty
              ? [fallbackServiceLabel.trim()]
              : const <String>[]);

    Widget listRow({
      required IconData icon,
      required String value,
      required bool showBorder,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
            Expanded(child: Text(value, style: _fieldValueTextStyle)),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: documentsStream,
      builder: (context, snapshot) {
        final verifiedDocs = snapshot.hasData
            ? snapshot.data!.docs
                  .where((d) => (d.data()['status'] as bool?) == true)
                  .toList(growable: false)
            : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final certificateNames = verifiedDocs
            .map((d) => (d.data()['name'] as String?)?.trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              title: 'Caregiver details',
              hint: 'Profile info from this caregiver.',
            ),
            const SizedBox(height: 4),
            _centerAvatar(caregiverName, caregiverPhotoUrl),
            _buildTabContent([
              _buildInfoRow(
                icon: Icons.person,
                title: 'Name',
                value: caregiverName,
              ),
              _buildInfoRow(
                icon: Icons.info_outline_rounded,
                title: 'Bio',
                value: bioRaw.isNotEmpty ? bioRaw : 'Unavailable',
              ),
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: caregiverLocation,
                showBorder: false,
              ),
            ]),
            const SizedBox(height: 14),
            _buildSectionHeader(title: 'Services provided'),
            if (servicesList.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Services unavailable',
                  explanation: 'Caregiver has not listed services yet.',
                ),
              )
            else
              _buildTabContent([
                for (var i = 0; i < servicesList.length; i++)
                  listRow(
                    icon: Icons.medical_services_outlined,
                    value: servicesList[i],
                    showBorder: i != servicesList.length - 1,
                  ),
              ]),
            const SizedBox(height: 14),
            _buildSectionHeader(title: 'Certificates'),
            if (!snapshot.hasData)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Certificates unavailable',
                  explanation: documentsStream is Stream<Never>
                      ? 'No certificates available.'
                      : 'Loading certificates...',
                ),
              )
            else if (certificateNames.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Certificates unavailable',
                  explanation: 'No verified certificates yet.',
                ),
              )
            else
              _buildTabContent([
                for (var i = 0; i < certificateNames.length; i++)
                  listRow(
                    icon: Icons.verified_outlined,
                    value: certificateNames[i],
                    showBorder: i != certificateNames.length - 1,
                  ),
              ]),
          ],
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildClientDetailsTab() {
    final booking = _booking ?? const <String, dynamic>{};
    final user = _userData ?? const <String, dynamic>{};

    final ownerName =
        normalizeString(user['name']) ??
        normalizeString(booking['userName']) ??
        'Client';
    final ownerPhone =
        normalizeString(user['phone']) ??
        normalizeString(booking['userPhone']) ??
        '—';
    final personName =
        normalizeString(booking['personName']) ??
        normalizeString(user['defaultPerson']) ??
        '—';
    final personLabel =
        normalizeString(booking['personLabel']) ?? 'Care recipient';
    final careLocation =
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['address']) ??
        normalizeString(user['defaultAddress']) ??
        '—';
    final notes =
        normalizeString(booking['personNotes'] ?? booking['notes']) ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(title: 'Client details'),
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
              value: careLocation,
            ),
            _buildInfoRow(
              icon: Icons.accessibility_new_rounded,
              title: 'Primary person',
              value:
                  '$personName (${personLabel.trim().isEmpty ? '—' : personLabel.trim()})',
              showBorder: notes.isNotEmpty,
            ),
            if (notes.isNotEmpty)
              _buildInfoContentRow(
                icon: Icons.sticky_note_2_outlined,
                title: 'Notes',
                value: notes,
              ),
          ]),
        ],
      ),
    );
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

  Widget _buildEmergencyContactsTab() {
    final contacts = _extractEmergencyContacts(_userData);
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
            (contacts[i]['name'] ?? 'Emergency contact').toString(),
            (contacts[i]['photoUrl'] as String?)?.trim(),
          ),
          _buildTabContent([
            _buildInfoRow(
              icon: Icons.person,
              title: 'Name',
              value: (contacts[i]['name'] ?? 'Emergency contact').toString(),
            ),
            _buildInfoRow(
              icon: Icons.family_restroom_rounded,
              title: 'Relationship',
              value: (contacts[i]['relationship'] ?? 'Relationship not set')
                  .toString(),
            ),
            Builder(
              builder: (context) {
                final phone = (contacts[i]['phone'] ?? '').toString().trim();
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
  }

  Widget _buildClientDetailsTabForCaregiver() {
    final booking = _booking ?? const <String, dynamic>{};
    final user = _userData ?? const <String, dynamic>{};

    final person = _resolvePersonDisplay(booking);
    final ownerName =
        normalizeString(user['name']) ??
        normalizeString(booking['userName']) ??
        'Booking owner';
    final ownerPhone =
        normalizeString(user['phone']) ??
        normalizeString(booking['userPhone']) ??
        '-';
    final ownerAddress =
        normalizeString(user['defaultAddress']) ??
        normalizeString(user['address']) ??
        normalizeString(booking['address']) ??
        '-';
    final ownerPhotoUrl =
        (normalizeString(user['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(user['photoUrl'])!.trim()
        : (normalizeString(user['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(user['imageUrl'])!.trim()
              : null));
    final notes =
        normalizeString(booking['personNotes'] ?? booking['notes']) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Client details'),
        const SizedBox(height: 4),
        Center(
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
              radius: 34,
              photoUrl: person.photoUrl,
              label: person.name,
            ),
          ),
        ),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.person,
            title: 'Client name',
            value: person.name,
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Client contact',
            value: person.phone,
          ),
          _buildInfoRow(
            icon: Icons.family_restroom_rounded,
            title: 'Relationship',
            value: person.label,
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Location',
            value: person.address,
            showBorder: notes.trim().isNotEmpty,
          ),
          if (notes.trim().isNotEmpty)
            _buildInfoContentRow(
              icon: Icons.sticky_note_2_outlined,
              title: 'Additional notes',
              value: notes.trim(),
            ),
        ]),
        const SizedBox(height: 14),
        _buildSectionHeader(title: 'Booking owner'),
        const SizedBox(height: 4),
        Center(
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
              radius: 34,
              photoUrl: ownerPhotoUrl,
              label: ownerName,
            ),
          ),
        ),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.person,
            title: 'Owner name',
            value: ownerName,
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Owner contact',
            value: ownerPhone,
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Location',
            value: ownerAddress,
            showBorder: false,
          ),
        ]),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildLocationTab({
    required String caregiverAddress,
    required String bookingAddress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Location'),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.location_on,
            title: 'Caregiver base',
            value: caregiverAddress,
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Booking address',
            value: bookingAddress,
            showBorder: false,
          ),
        ]),
      ],
    );
  }

  Widget _buildScheduleTab(Map<String, dynamic> booking) {
    final date = normalizeString(booking['date']) ?? '';
    final time = normalizeString(booking['time']) ?? '';
    final startTime = normalizeString(booking['startTime']) ?? '';
    final endTime = normalizeString(booking['endTime']) ?? '';
    final scheduledDate = normalizeString(booking['scheduledDate']) ?? '';

    final dateLabel = scheduledDate.isNotEmpty ? scheduledDate : date;
    final timeLabel = (startTime.isNotEmpty && endTime.isNotEmpty)
        ? '${_formatTime(startTime)} - ${_formatTime(endTime)}'
        : (time.isNotEmpty ? _formatTime(time) : '');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = _scheduleSelectedDay ?? today;
    final selectedKey = _ymd(selectedDay);

    _scheduleSelectedDay ??= today;

    DateTime? parseYmd(String raw) {
      try {
        return DateFormat('yyyy-MM-dd').parse(raw);
      } catch (_) {
        return null;
      }
    }

    DateTime? bookingDay = dateLabel.isNotEmpty ? parseYmd(dateLabel) : null;
    if (bookingDay == null && _isPreviewMode) {
      bookingDay = selectedDay;
    }
    final caregiverIdFromBooking = (booking['caregiverId'] as String?)?.trim();
    final caregiverId = caregiverIdFromBooking?.isNotEmpty == true
        ? caregiverIdFromBooking!
        : (widget.caregiverId?.trim() ?? '');
    final bookingStart = startTime.isNotEmpty
        ? _parseStoredTime(startTime)
        : null;
    final bookingEnd = endTime.isNotEmpty ? _parseStoredTime(endTime) : null;

    if (bookingDay == null) {
      return Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Schedule'),
            _buildTabContent([
              _buildInfoRow(
                icon: Icons.calendar_month,
                title: 'Date',
                value: dateLabel.isNotEmpty ? _formatDate(dateLabel) : '-',
              ),
              _buildInfoRow(
                icon: Icons.access_time,
                title: 'Time',
                value: timeLabel.isNotEmpty ? timeLabel : '-',
                showBorder: false,
              ),
            ]),
          ],
        ),
      );
    }

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
      bool strike = false,
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
                  decoration: strike ? TextDecoration.lineThrough : null,
                  color: foreground.withValues(alpha: 0.78),
                ),
              ),
            ],
          ],
        ),
      );
    }

    String dayTitle(DateTime d) => DateFormat('EEEE').format(d);
    String daySubtitle(DateTime d) => DateFormat('d MMMM yyyy').format(d);

    Widget bookedTimelineDayView({
      required TimeOfDay windowStart,
      required TimeOfDay windowEnd,
      required List<_TimeRange> taken,
      TimeOfDay? bookingStart,
      TimeOfDay? bookingEnd,
      bool showBooking = false,
    }) {
      int toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
      int floorToHour(int m) => (m ~/ 60) * 60;
      int ceilToHour(int m) => ((m + 59) ~/ 60) * 60;

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

      if (showBooking && bookingStart != null && bookingEnd != null) {
        final s = toMinutes(bookingStart);
        final e = toMinutes(bookingEnd);
        if (e > s) {
          blocks.add((
            start: s,
            end: e,
            color: const Color(0xFF71CBBE),
            title: 'Your booking',
          ));
        }
      }

      final baseStart = toMinutes(windowStart);
      final baseEnd = toMinutes(windowEnd);
      final allStarts = <int>[baseStart, ...blocks.map((e) => e.start)];
      final allEnds = <int>[baseEnd, ...blocks.map((e) => e.end)];
      var startMin = floorToHour(allStarts.reduce((a, b) => a < b ? a : b));
      var endMin = ceilToHour(allEnds.reduce((a, b) => a > b ? a : b));
      if (endMin <= startMin) endMin = startMin + 60;

      final hourCount = ((endMin - startMin) / 60).ceil();
      const leftGutter = 54.0;
      const pxPerMin = 1.25; // ~75px per hour
      final canvasHeight = (endMin - startMin) * pxPerMin;

      blocks.sort((a, b) => a.start.compareTo(b.start));
      final laneEnds = <int>[];
      final laidOut =
          <({int start, int end, int lane, Color color, String title})>[];
      for (final item in blocks) {
        int lane = -1;
        for (int i = 0; i < laneEnds.length; i++) {
          if (item.start >= laneEnds[i]) {
            lane = i;
            break;
          }
        }
        if (lane == -1) {
          lane = laneEnds.length;
          laneEnds.add(item.end);
        } else {
          laneEnds[lane] = item.end;
        }
        laidOut.add((
          start: item.start,
          end: item.end,
          lane: lane,
          color: item.color,
          title: item.title,
        ));
      }
      final lanes = laneEnds.isEmpty ? 1 : laneEnds.length;

      String labelForMinute(int absoluteMin) {
        final h = (absoluteMin ~/ 60).toString().padLeft(2, '0');
        final m = (absoluteMin % 60).toString().padLeft(2, '0');
        return '$h:$m';
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              height: canvasHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: leftGutter,
                    child: Column(
                      children: [
                        for (int i = 0; i <= hourCount; i++) ...[
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final laneGap = 8.0;
                        final laneWidth =
                            (c.maxWidth - (laneGap * (lanes - 1))) / lanes;
                        return Stack(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                    onTap: isPast
                        ? null
                        : () => setState(() => _scheduleSelectedDay = d),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 54,
                      decoration: BoxDecoration(
                        color: isSelected ? _accentBlue : Colors.transparent,
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
                                      alpha: isPast ? 0.22 : 0.45,
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
                                        ? Colors.black.withValues(alpha: 0.30)
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
            final available = entry['available'] as bool? ?? true;
            final startRaw = entry['start']?.toString() ?? '08:00';
            final endRaw = entry['end']?.toString() ?? '18:00';
            final start =
                _parseStoredTime(startRaw) ??
                const TimeOfDay(hour: 8, minute: 0);
            final end =
                _parseStoredTime(endRaw) ??
                const TimeOfDay(hour: 18, minute: 0);
            map[weekday] = (available: available, start: start, end: end);
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
              excludeBookingId: widget.bookingId,
            );
            if (!mounted) return;
            setState(() {
              _scheduleTakenCache[selectedKey] = next;
              _scheduleLoadingTaken.remove(selectedKey);
            });
          });
        }

        final taken = _scheduleTakenCache[selectedKey] ?? const <_TimeRange>[];
        final isLoadingTaken =
            caregiverId.isNotEmpty &&
            !_scheduleTakenCache.containsKey(selectedKey);

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dateStrip(selectedDay),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    dayTitle(selectedDay),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _profileDarkText,
                    ),
                  ),
                ),
                Text(
                  daySubtitle(selectedDay),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        );

        final timelineItems = <Widget>[];

        if (isLoadingTaken) {
          timelineItems.add(
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
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
          final isBookingDay = _ymd(selectedDay) == _ymd(bookingDay!);
          final bookingEndResolved = (isBookingDay && bookingStart != null)
              ? (bookingEnd ??
                    TimeOfDay(
                      hour:
                          (bookingStart.hour +
                              ((bookingStart.minute + 15) ~/ 60)) %
                          24,
                      minute: (bookingStart.minute + 15) % 60,
                    ))
              : null;

          timelineItems.add(
            bookedTimelineDayView(
              windowStart: availableWindow.$1,
              windowEnd: availableWindow.$2,
              taken: taken,
              bookingStart: bookingStart,
              bookingEnd: bookingEndResolved,
              showBooking: isBookingDay && bookingStart != null,
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader(title: 'Schedule'),
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
          ),
        );
      },
    );
  }

  Widget _buildReviewsTab(String caregiverId) {
    final caregiverName =
        normalizeString(_caregiverData?['name'])?.trim().isNotEmpty == true
        ? normalizeString(_caregiverData?['name'])!.trim()
        : 'Caregiver';
    final caregiverPhotoUrl =
        normalizeString(_caregiverData?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(_caregiverData?['photoUrl'])!.trim()
        : (normalizeString(_caregiverData?['imageUrl'])?.trim().isNotEmpty ==
                  true
              ? normalizeString(_caregiverData?['imageUrl'])!.trim()
              : null);

    if (caregiverId.isEmpty) {
      return _buildUnavailablePlaceholder(
        message: 'Reviews unavailable',
        explanation: 'No caregiver assigned yet.',
        centerVertically: true,
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('reviews')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildUnavailablePlaceholder(
            message: 'Reviews unavailable',
            explanation: 'Unable to load reviews right now.',
            centerVertically: true,
          );
        }
        if (!snapshot.hasData) {
          return _buildUnavailablePlaceholder(
            message: 'Reviews unavailable',
            explanation: 'Loading reviews...',
            centerVertically: true,
          );
        }

        final allDocs = snapshot.data!.docs.toList(growable: false)
          ..sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

        final counts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        var totalRating = 0;
        for (final doc in allDocs) {
          final rating = _coerceRating(doc.data()['rating']);
          if (rating <= 0) continue;
          counts[rating] = (counts[rating] ?? 0) + 1;
          totalRating += rating;
        }
        final totalCount = counts.values.fold<int>(0, (a, b) => a + b);
        final average = totalCount == 0 ? 0.0 : totalRating / totalCount;

        final selected = _selectedRatingFilter;
        final docs = selected == null
            ? allDocs
            : allDocs
                  .where((d) => _coerceRating(d.data()['rating']) == selected)
                  .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Reviews'),
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 124,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        for (final star in const [5, 4, 3, 2, 1]) ...[
                          _ratingBar(
                            star: star,
                            count: counts[star] ?? 0,
                            total: totalCount,
                          ),
                          if (star != 1) const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildSectionHeader(title: 'Filters'),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _filterChip(
                    label: 'All ($totalCount)',
                    selected: selected == null,
                    onTap: () => setState(() => _selectedRatingFilter = null),
                  ),
                  const SizedBox(width: 6),
                  for (final star in const [5, 4, 3, 2, 1]) ...[
                    _filterChip(
                      label: '$star (${counts[star] ?? 0})',
                      selected: selected == star,
                      onTap: () => setState(() => _selectedRatingFilter = star),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Reviews unavailable',
                  explanation: totalCount == 0
                      ? 'No reviews yet.'
                      : 'No reviews for this filter.',
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final personName =
                      (data['personName'] as String?)?.trim() ?? 'User';
                  final userId = (data['userId'] as String?)?.trim() ?? '';
                  final service = (data['service'] as String?)?.trim() ?? '';
                  final feedback = (data['feedback'] as String?)?.trim() ?? '';
                  final caregiverReply =
                      (data['caregiverReply'] as String?)?.trim() ?? '';
                  final rating = _coerceRating(data['rating']);
                  final createdAt = data['createdAt'] as Timestamp?;
                  final relative = _formatRelative(createdAt);
                  final dateLabel = _formatReviewDate(createdAt);

                  return Container(
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<_UserMini>(
                          future: _fetchUserMini(
                            userId: userId,
                            fallbackName: personName,
                          ),
                          builder: (context, userSnap) {
                            final user =
                                userSnap.data ??
                                _UserMini(name: personName, photoUrl: null);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _reviewAvatar(user),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    user.name.trim().isNotEmpty
                                        ? user.name.trim()
                                        : personName,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: _profileDarkText,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _starRow(rating.toDouble(), size: 16),
                        if (service.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Service: $service',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.58),
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
                                : Colors.black.withValues(alpha: 0.52),
                          ),
                        ),
                        if (caregiverReply.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildCaregiverReply(
                            caregiverName: caregiverName,
                            caregiverPhotoUrl: caregiverPhotoUrl,
                            reply: caregiverReply,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              relative.isNotEmpty ? relative : dateLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.45),
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

  // ignore: unused_element
  Widget _buildInfoRowWithTrailing({
    required IconData icon,
    required String title,
    required String value,
    required Widget trailing,
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
          const SizedBox(width: 10),
          trailing,
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

  Widget _buildSectionHeader({
    required String title,
    String? hint,
    EdgeInsets padding = const EdgeInsets.fromLTRB(4, 6, 4, 8),
    double hintTopSpacing = 3,
    bool tightHint = false,
  }) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: padding,
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
            SizedBox(height: hintTopSpacing),
            Text(
              trimmedHint,
              strutStyle: tightHint
                  ? const StrutStyle(
                      forceStrutHeight: true,
                      height: 1.0,
                      leading: 0,
                    )
                  : null,
              textHeightBehavior: tightHint
                  ? const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    )
                  : null,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.50),
                height: tightHint ? 1.0 : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingDetailsTab() {
    final booking = _booking;
    if (booking == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Loading booking details...'),
      );
    }
    final date = normalizeString(booking['date']);
    final time = normalizeString(booking['time']);
    final payment = normalizeString(booking['paymentMethod']) ?? 'Unknown';
    final notes =
        normalizeString(booking['personNotes'] ?? booking['notes']) ?? '';
    final personDisplay = _resolvePersonDisplay(booking);
    final services = extractServicePreferencesList(
      booking['servicePreferences'] ??
          booking['services'] ??
          booking['selectedServices'],
    );
    final fallbackServiceLabel = extractServiceLabelFromFirestore(booking);
    final servicesValue = services.isNotEmpty
        ? services.join(', ')
        : (fallbackServiceLabel.trim().isNotEmpty
              ? fallbackServiceLabel.trim()
              : 'Unavailable');
    final ownerName = (_userData?['name'] as String?) ?? 'You';
    final ownerPhone = (_userData?['phone'] as String?) ?? 'No contact';

    final caregiver = _caregiverData ?? const <String, dynamic>{};
    final caregiverName =
        normalizeString(caregiver['name']) ??
        normalizeString(booking['caregiverName']) ??
        'Caregiver';
    final caregiverPhone =
        normalizeString(caregiver['phone']) ??
        normalizeString(caregiver['phoneNumber']) ??
        normalizeString(booking['caregiverPhone']) ??
        '-';
    final caregiverAddress =
        normalizeString(caregiver['defaultAddress']) ??
        normalizeString(caregiver['address']) ??
        normalizeString(caregiver['area']) ??
        'Location not provided';
    final caregiverPhotoUrl =
        (normalizeString(caregiver['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(caregiver['photoUrl'])!.trim()
        : (normalizeString(caregiver['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(caregiver['imageUrl'])!.trim()
              : null));
    final caregiverServices = extractServicePreferencesList(
      caregiver['servicePreferences'] ?? caregiver['services'],
    );
    final caregiverServiceFallback =
        normalizeString(caregiver['service']) ?? '';
    final caregiverServicesValue = caregiverServices.isNotEmpty
        ? caregiverServices.join(', ')
        : (caregiverServiceFallback.trim().isNotEmpty
              ? caregiverServiceFallback.trim()
              : servicesValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Caregiver'),
        const SizedBox(height: 4),
        _centerAvatar(caregiverName, caregiverPhotoUrl),
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
        _centerAvatar(personDisplay.name, personDisplay.photoUrl),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.person,
            title: 'Name',
            value: personDisplay.name,
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Contact',
            value: personDisplay.phone,
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Location',
            value: personDisplay.address,
            showBorder: false,
          ),
        ]),
        const SizedBox(height: 14),
        _buildSectionHeader(
          title: 'Booking details',
          hint: 'Live details pulled from the booking record.',
        ),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.medical_services_outlined,
            title: 'Services',
            value: servicesValue,
          ),
          _buildInfoRow(
            icon: Icons.calendar_month,
            title: 'Booked date',
            value: _formatDate(date ?? ''),
          ),
          _buildInfoRow(
            icon: Icons.access_time,
            title: 'Time',
            value: _formatTime(time ?? ''),
          ),
          _buildInfoRow(
            icon: Icons.person,
            title: 'Booked by',
            value: ownerName,
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Owner contact',
            value: ownerPhone,
          ),
          _buildInfoRow(
            icon: Icons.payment,
            title: 'Payment',
            value: payment,
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
  }

  Widget _buildBookingSummaryTab(
    BuildContext context,
    Map<String, dynamic> booking,
    String caregiverId,
    String caregiverName,
  ) {
    final stageSnapshots = _extractStageSnapshots(booking);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            title: 'Stage photos',
            hint: 'Captured during the caregiver session.',
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            hintTopSpacing: 0,
            tightHint: true,
          ),
          if (stageSnapshots.isEmpty)
            Transform.translate(
              offset: const Offset(0, -60),
              child: Padding(
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
              ),
            )
          else
            Transform.translate(
              offset: const Offset(0, -60),
              child: Padding(
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
                    final timeLabel = dt == null
                        ? '-'
                        : _formatSnapshotTime(dt);
                    final photoUrl = (entry['photoUrl']?.toString() ?? '')
                        .trim();

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
                        decoration: _premiumCardDecoration(radius: 16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: photoUrl.isEmpty
                                  ? Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
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
                                      placeholder: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      ),
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
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
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
                                      color: Colors.black.withValues(
                                        alpha: 0.6,
                                      ),
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

  Future<void> _startSessionFromCaregiverView() async {
    final booking = _booking;
    if (booking == null) return;
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.trim().isEmpty) return;

    final personId = normalizeString(booking['personId']) ?? '';
    var caregiverName =
        normalizeString(_caregiverData?['name']) ??
        normalizeString(booking['caregiverName']) ??
        'Caregiver';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId.trim())
          .get();
      final data = doc.data();
      final raw = data?['name'];
      if (raw is String && raw.trim().isNotEmpty) caregiverName = raw.trim();
    } catch (_) {}

    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .set({
          'trackingCaregiverId': caregiverId.trim(),
          if (personId.trim().isNotEmpty) 'trackingPersonId': personId.trim(),
          'trackingUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackCaregiverScreen(
          bookingId: widget.bookingId,
          caregiverName: caregiverName,
          caregiverId: caregiverId.trim(),
          personId: personId.trim().isNotEmpty ? personId.trim() : null,
          showStatusUpdateButton: true,
          showActionFrontSheet: true,
        ),
      ),
    );
  }

  Future<Position?> _getDevicePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // ignore: unused_element
  Future<void> _openEmergencyAlertSheet() async {
    final contacts = _extractEmergencyContacts(_userData);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _EmergencyAlertBottomSheet(
          contacts: contacts,
          onSubmit: (ids, reason) async {
            final pos = await _getDevicePosition();
            if (pos == null) {
              throw const _EmergencyAlertError(
                message: 'Location permission is required for SOS.',
              );
            }
            final functions = FirebaseFunctions.instanceFor(
              region: 'us-central1',
            );
            await functions.httpsCallable('handleSOSAlert').call({
              'lat': pos.latitude,
              'lng': pos.longitude,
              'reason': reason.trim().isNotEmpty
                  ? reason.trim()
                  : 'Emergency alert',
              'notifyContactIds': ids.toList(growable: false),
            });
          },
          onCompleted: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Emergency alert started.')),
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildSelectedPersonHeaderSummary({
    required String? photoUrl,
    required String name,
    required String label,
    required String address,
    required String serviceLabel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultProfileAvatar(radius: 18, photoUrl: photoUrl, label: name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isNotEmpty ? name.trim() : 'Selected person',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeaderPill(
                      icon: Icons.accessibility_new_rounded,
                      text: label,
                    ),
                    _buildHeaderPill(
                      icon: Icons.medical_services_outlined,
                      text: serviceLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.62),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _caregiverSessionFrontSheet({
    required String personName,
    required String personLabel,
    required String location,
    required String? personPhotoUrl,
  }) {
    final title = personName.trim().isNotEmpty ? personName.trim() : 'Person';
    final subtitleParts = <String>[];
    if (personLabel.trim().isNotEmpty) subtitleParts.add(personLabel.trim());
    if (location.trim().isNotEmpty) subtitleParts.add(location.trim());
    final subtitle = subtitleParts.join(' • ');

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DefaultProfileAvatar(
                  radius: 22,
                  photoUrl: personPhotoUrl,
                  label: title,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _profileDarkText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle.isNotEmpty ? subtitle : 'Selected person',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.54),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startSessionFromCaregiverView,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Start session'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caregiverSessionStartFrontSheet({
    required String? personPhotoUrl,
    required String personName,
    required String personLabel,
    required String personAddress,
    required String serviceLabel,
  }) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _avatarOutlineColor, width: 2.2),
                  ),
                  child: DefaultProfileAvatar(
                    radius: 20,
                    photoUrl: personPhotoUrl,
                    label: personName,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName.trim().isNotEmpty
                            ? personName.trim()
                            : 'Selected person',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _profileDarkText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [personLabel, serviceLabel]
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.54),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        personAddress.trim().isNotEmpty
                            ? personAddress.trim()
                            : 'Care location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startSessionFromCaregiverView,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: const Text('Start session'),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(
          title: 'Booking Details',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Center(child: Text(_error!)),
      );
    }
    if (!_isPreviewMode && (_notFound || _booking == null)) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(
          title: 'Booking Details',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final booking = _booking ?? const <String, dynamic>{};
    final isCaregiverView = widget.caregiverView;
    final caregiverName =
        normalizeString(booking['caregiverName']) ??
        normalizeString(_caregiverData?['name']) ??
        'Caregiver';
    final caregiverPhoto =
        (normalizeString(_caregiverData?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(_caregiverData?['photoUrl'])!.trim()
        : (normalizeString(_caregiverData?['imageUrl'])?.trim().isNotEmpty ==
                  true
              ? normalizeString(_caregiverData?['imageUrl'])!.trim()
              : _defaultAvatarUrl));
    final rawServiceLabel = _booking == null
        ? ''
        : extractServiceLabelFromFirestore(booking);
    final service = rawServiceLabel.isNotEmpty ? rawServiceLabel : 'Home care';
    // Keep booking status available for downstream sections if needed later.
    // (No longer shown in the header card.)
    final caregiverId =
        normalizeString(booking['caregiverId']) ??
        (widget.caregiverId?.trim() ?? '');
    final caregiverDefaultAddress =
        normalizeString(_caregiverData?['defaultAddress']) ??
        normalizeString(_caregiverData?['address']) ??
        normalizeString(_caregiverData?['area']) ??
        'Location not provided';

    final documentsStream = (!isCaregiverView && caregiverId.isNotEmpty)
        ? FirebaseFirestore.instance
              .collection('documents')
              .where('caregiverId', isEqualTo: caregiverId)
              .snapshots()
        : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    final reviewsCountStream = (!isCaregiverView && caregiverId.isNotEmpty)
        ? FirebaseFirestore.instance
              .collection('reviews')
              .where('caregiverId', isEqualTo: caregiverId)
              .snapshots()
              .map((snap) => snap.docs.length)
        : Stream<int>.value(0);
    final verifiedDocsCountStream = (!isCaregiverView && caregiverId.isNotEmpty)
        ? documentsStream.map(
            (snap) => snap.docs
                .where((d) => (d.data()['status'] as bool?) == true)
                .length,
          )
        : Stream<int>.value(0);
    final clientsCountStream = (!isCaregiverView && caregiverId.isNotEmpty)
        ? FirebaseFirestore.instance
              .collection('bookings')
              .where('caregiverId', isEqualTo: caregiverId)
              .where('status', isEqualTo: 'COMPLETED')
              .snapshots()
              .map((snap) => snap.docs.length)
        : Stream<int>.value(0);

    final hasBookingTab = !_isPreviewMode && !widget.hideBookingDetailsTab;
    final showScheduleTab = _isPreviewMode && !isCaregiverView;
    final normalizedStatus = _normalizeBookingStatusForListener(
      normalizeString(booking['status']) ?? '',
    );
    final showBookingSummaryTab = normalizedStatus == 'COMPLETED';

    late final List<String> tabLabels;
    late final int bookingDetailsTabIndex;
    late final int bookingSummaryTabIndex;
    late final int scheduleTabIndex;
    late final int reviewsTabIndex;
    late final int emergencyTabIndex;

    if (isCaregiverView) {
      tabLabels = <String>[
        'Client details',
        'Emergency contact',
        'Booking details',
        if (showBookingSummaryTab) 'Booking summary',
      ];
      bookingDetailsTabIndex = 2;
      bookingSummaryTabIndex = showBookingSummaryTab ? 3 : -1;
      scheduleTabIndex = -1;
      reviewsTabIndex = -1;
      emergencyTabIndex = 1;
    } else {
      final nextLabels = <String>['Caregiver details'];
      var nextBookingDetailsIndex = -1;
      var nextBookingSummaryIndex = -1;
      var nextScheduleIndex = -1;

      if (hasBookingTab) {
        nextBookingDetailsIndex = nextLabels.length;
        nextLabels.add('Booking details');
      }

      if (showBookingSummaryTab) {
        nextBookingSummaryIndex = nextLabels.length;
        nextLabels.add('Booking summary');
      }

      if (showScheduleTab) {
        nextScheduleIndex = nextLabels.length;
        nextLabels.add('Schedule');
      }

      final nextReviewsIndex = nextLabels.length;
      nextLabels.add('Reviews');

      tabLabels = nextLabels;
      bookingDetailsTabIndex = nextBookingDetailsIndex;
      bookingSummaryTabIndex = nextBookingSummaryIndex;
      scheduleTabIndex = nextScheduleIndex;
      reviewsTabIndex = nextReviewsIndex;
      emergencyTabIndex = -1;
    }

    final selectedIndex = _selectedTabIndex
        .clamp(0, tabLabels.length - 1)
        .toInt();

    Widget selectedTabContent() {
      final index = selectedIndex;
      if (isCaregiverView && index == 0) {
        return _buildClientDetailsTabForCaregiver();
      }
      if (isCaregiverView && index == emergencyTabIndex) {
        return _buildEmergencyContactsTab();
      }
      if (!isCaregiverView && index == 0) {
        return _buildCaregiverDetailsTab(
          caregiver: _caregiverData,
          documentsStream: documentsStream,
        );
      }
      if (hasBookingTab && index == bookingDetailsTabIndex) {
        return _buildBookingDetailsTab();
      }
      if (bookingSummaryTabIndex >= 0 && index == bookingSummaryTabIndex) {
        return _buildBookingSummaryTab(
          context,
          booking,
          caregiverId,
          caregiverName,
        );
      }
      if (scheduleTabIndex >= 0 && index == scheduleTabIndex) {
        return _buildScheduleTab(booking);
      }
      if (reviewsTabIndex >= 0 && index == reviewsTabIndex) {
        return _buildReviewsTab(caregiverId);
      }
      return const SizedBox.shrink();
    }

    final clientPhoto =
        (normalizeString(_userData?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(_userData?['photoUrl'])!.trim()
        : (normalizeString(_userData?['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(_userData?['imageUrl'])!.trim()
              : _defaultAvatarUrl));

    final personDisplay = _resolvePersonDisplay(booking);
    final clientName =
        normalizeString(_userData?['name']) ??
        normalizeString(booking['userName']) ??
        'Client';

    final headerName = isCaregiverView ? clientName : caregiverName;
    final headerPhoto = isCaregiverView ? clientPhoto : caregiverPhoto;
    final headerAddress = isCaregiverView
        ? personDisplay.address
        : caregiverDefaultAddress;

    final coverPhoto = headerPhoto.trim().isNotEmpty
        ? headerPhoto.trim()
        : _defaultAvatarUrl;

    const double headerCardOverlap = 96;
    final headerWithMetrics = isCaregiverView
        ? SizedBox(
            height: 220 + headerCardOverlap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(height: 220),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildHeroCover(coverPhoto),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: _buildHeaderCard(
                    name: headerName,
                    serviceLabel: service,
                    servicePreferences: const [],
                    defaultAddress: headerAddress,
                    clientsCount: 0,
                    verifiedDocsCount: 0,
                    reviewsCount: 0,
                    photoUrl: headerPhoto,
                    hideMetrics: true,
                    showServiceSubtitle: true,
                  ),
                ),
              ],
            ),
          )
        : StreamBuilder<int>(
            stream: clientsCountStream,
            builder: (context, clientsSnap) {
              final clientsCount = clientsSnap.data ?? 0;
              return StreamBuilder<int>(
                stream: verifiedDocsCountStream,
                builder: (context, docsSnap) {
                  final verifiedDocs = docsSnap.data ?? 0;
                  return StreamBuilder<int>(
                    stream: reviewsCountStream,
                    builder: (context, reviewsSnap) {
                      final reviewsCount = reviewsSnap.data ?? 0;
                      return SizedBox(
                        height: 220 + headerCardOverlap,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: SizedBox(height: 220),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: _buildHeroCover(coverPhoto),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 0,
                              child: _buildHeaderCard(
                                name: caregiverName,
                                serviceLabel: service,
                                servicePreferences: const [],
                                defaultAddress: caregiverDefaultAddress,
                                clientsCount: clientsCount,
                                verifiedDocsCount: verifiedDocs,
                                reviewsCount: reviewsCount,
                                photoUrl: caregiverPhoto,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
    _scheduleAutoSheetExtentUpdate();

    final tabSelector = _buildOtherInfoTabs(
      labels: tabLabels,
      selectedIndex: selectedIndex,
      onSelected: _selectTab,
    );

    final sheetInitialExtentRaw =
        _autoInitialSheetExtent ?? _sheetFallbackInitialExtentRaw;
    const double sheetMaxExtentRaw = _sheetMaxExtentRaw;

    final sheetInitialExtent = sheetInitialExtentRaw.clamp(
      _sheetDefaultMinExtentRaw,
      _sheetDefaultMaxInitialExtentRaw,
    );
    final sheetMaxExtent = math
        .max(sheetMaxExtentRaw.clamp(0.0, 1.0), sheetInitialExtent)
        .clamp(sheetInitialExtent, 1.0);

    final sheetMinExtent = (_isPreviewMode && _canBookFromSchedule)
        ? math.min(sheetInitialExtent, 0.62)
        : sheetInitialExtent;

    final previewDenom = (sheetMaxExtent - sheetMinExtent);
    final effectivePanelT = previewDenom <= 0
        ? 0.0
        : (_panelSeeded
                  ? _panelController.value
                  : ((sheetInitialExtent - sheetMinExtent) / previewDenom))
              .clamp(0.0, 1.0);
    final effectiveSheetExtent =
        sheetMinExtent + (previewDenom * effectivePanelT);
    final showPreviewCta = _canBookFromSchedule && widget.showPreviewFrontSheet;
    final previewT = previewDenom <= 0
        ? 0.0
        : ((effectiveSheetExtent - sheetMinExtent) / previewDenom).clamp(
            0.0,
            1.0,
          );
    final hidePreviewCta = showPreviewCta && previewT > 0.55;
    final showTrackFrontSheet =
        widget.showTrackFrontSheet &&
        !isCaregiverView &&
        !_isPreviewMode &&
        _showTrackButton &&
        caregiverId.trim().isNotEmpty;
    final hideTrackFrontSheet = showTrackFrontSheet && previewT > 0.55;
    final showCaregiverFrontSheet =
        isCaregiverView && !_isPreviewMode && normalizedStatus != 'COMPLETED';
    final hideCaregiverFrontSheet = showCaregiverFrontSheet && previewT > 0.55;
    final String? distance = null;
    final String? eta = null;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final double previewFrontBottom = hidePreviewCta
        ? -110.0
        : (bottomInset + 2).clamp(4.0, double.infinity).toDouble();
    final double trackFrontBottom = hideTrackFrontSheet
        ? -110.0
        : (bottomInset + 2).clamp(4.0, double.infinity).toDouble();
    final double caregiverFrontBottom = hideCaregiverFrontSheet
        ? -140.0
        : (bottomInset + 2).clamp(4.0, double.infinity).toDouble();
    final panelBackdropAlpha = (lerpDouble(0.0, 0.08, effectivePanelT) ?? 0.0)
        .clamp(0.0, 0.12)
        .toDouble();

    final content = Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [KeyedSubtree(key: _metricsKey, child: headerWithMetrics)],
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
        LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            _panelMinExtent = sheetMinExtent;
            _panelMaxExtent = sheetMaxExtent;
            final denom = (sheetMaxExtent - sheetMinExtent);
            final desiredInitialT = denom <= 0
                ? 0.0
                : ((sheetInitialExtent - sheetMinExtent) / denom).clamp(
                    0.0,
                    1.0,
                  );
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
                sheetMinExtent + (denom * _panelController.value);
            final t = denom <= 0 ? 0.0 : _panelController.value;
            final appBarT = ((extentBase - 0.90) / 0.10)
                .clamp(0.0, 1.0)
                .toDouble();
            final topChromeInset =
                (lerpDouble(0, kToolbarHeight + 6.0, appBarT) ?? 0.0).clamp(
                  0.0,
                  double.infinity,
                );
            final previewVisible = showPreviewCta && !hidePreviewCta;
            final trackVisible = showTrackFrontSheet && !hideTrackFrontSheet;
            final caregiverVisible =
                showCaregiverFrontSheet && !hideCaregiverFrontSheet;
            final bottomCtaPadding = (previewVisible || trackVisible)
                ? 172.0
                : (caregiverVisible ? 212.0 : 0.0);

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
                      const SizedBox(height: 10),
                      tabSelector,
                      Divider(
                        height: 10,
                        thickness: 2,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const _NoOverscrollScrollBehavior(),
                          child: ListView(
                            controller: _panelScrollController,
                            padding: EdgeInsets.only(bottom: bottomCtaPadding),
                            physics: const ClampingScrollPhysics(),
                            children: [
                              FadeTransition(
                                opacity: _tabFade,
                                child: SlideTransition(
                                  position: _tabSlide,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      12,
                                    ),
                                    child: selectedTabContent(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (showTrackFrontSheet)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            left: 8,
            right: 8,
            bottom: trackFrontBottom,
            child: IgnorePointer(
              ignoring: hideTrackFrontSheet,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.black12.withValues(alpha: 0.08),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _trackFrontSheet(
                  caregiverName: caregiverName,
                  caregiverPhotoUrl: caregiverPhoto,
                  serviceLabel: service,
                  metaLine: [
                    if (distance?.trim().isNotEmpty == true) distance!.trim(),
                    if (eta?.trim().isNotEmpty == true) eta!.trim(),
                  ].join(' • '),
                ),
              ),
            ),
          ),
        if (showCaregiverFrontSheet)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            left: 8,
            right: 8,
            bottom: caregiverFrontBottom,
            child: IgnorePointer(
              ignoring: hideCaregiverFrontSheet,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.black12.withValues(alpha: 0.08),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _caregiverSessionStartFrontSheet(
                  personPhotoUrl: personDisplay.photoUrl,
                  personName: personDisplay.name,
                  personLabel: personDisplay.label,
                  personAddress: personDisplay.address,
                  serviceLabel: service,
                ),
              ),
            ),
          ),
        if (showPreviewCta)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            left: 8,
            right: 8,
            bottom: previewFrontBottom,
            child: IgnorePointer(
              ignoring: hidePreviewCta,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.black12.withValues(alpha: 0.08),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _previewFrontSheet(),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: _screenBackground,
      extendBodyBehindAppBar: true,
      appBar: buildProfileStyleAppBar(
        title: _isPreviewMode ? 'Caregiver Details' : 'Booking details',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(position: _entrySlide, child: content),
      ),
    );
  }
}

// _StatusChip removed (no longer used in this screen).

class _UserMini {
  const _UserMini({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;
}
