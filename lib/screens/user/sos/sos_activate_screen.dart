import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'sos_finding_screen.dart';

const Color _sosHeadingColor = Color(0xFF1B1D29);
const Color _sosSubTextColor = Color(0xFF4C4F65);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _cardBorderColor = Color(0xFFD1D6DE);
const double _cardRadius = 18;
const double _contentMaxWidth = 520;
const Color _reasonChipBorder = Color(0xFFCCCCCC);
const TextStyle _reasonChipBaseStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  height: 1.1,
);
const TextStyle _addressDropdownPrimaryStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: _sosHeadingColor,
  decoration: TextDecoration.none,
  height: 1.2,
);
const TextStyle _addressDropdownSecondaryStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w500,
  color: _sosSubTextColor,
  decoration: TextDecoration.none,
  height: 1.2,
);
const List<String> _sosReasons = [
  'Medical emergency',
  'Mobility support',
  'Security concern',
  'Personal aid',
];

class SosActivateScreen extends StatefulWidget {
  const SosActivateScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 2,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<SosActivateScreen> createState() => _SosActivateScreenState();
}

class _SosActivateScreenState extends State<SosActivateScreen>
    with TickerProviderStateMixin {
  late final AnimationController _holdController;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;
  bool _wasActive = false;

  int _selectedAddressIndex = 0;
  int _selectedReasonIndex = 0;
  bool _isHolding = false;
  bool _isTriggering = false;
  OverlayEntry? _addressDropdownEntry;
  List<_AddressRecord> _addressRecords = [];

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

  List<Map<String, dynamic>> _extractAddressList(Map<String, dynamic>? data) {
    final raw = data?['addresses'] ?? data?['address'];
    if (raw is Iterable) {
      return raw
          .map<Map<String, dynamic>>(_coerceAddressEntry)
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
    if (raw is Map) {
      return [_coerceAddressEntry(raw)];
    }
    return [];
  }

  Map<String, dynamic> _coerceAddressEntry(dynamic entry) {
    if (entry is Map<String, dynamic>) return Map<String, dynamic>.from(entry);
    if (entry is Map) return Map<String, dynamic>.from(entry);
    return {'title': '$entry'};
  }

  String _firstNonEmptyString(List<dynamic> options, String fallback) {
    for (final option in options) {
      if (option is String && option.trim().isNotEmpty) {
        return option.trim();
      }
    }
    return fallback;
  }

  String _addressLineText(Map<String, dynamic>? entry) => _firstNonEmptyString([
    entry?['addressLine'],
    entry?['line1'],
    entry?['fullAddress'],
    entry?['subtitle'],
    entry?['address'],
  ], 'No address details yet');

  String _addressNameText(Map<String, dynamic>? entry) => _firstNonEmptyString([
    entry?['name'],
    entry?['forWho'],
    entry?['title'],
    entry?['label'],
  ], 'Address');

  String _addressLabelOnly(Map<String, dynamic>? entry) => _firstNonEmptyString(
    [entry?['label'], entry?['tag'], entry?['type']],
    '',
  );

  _AddressRecord _userAddressRecord(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final data = snapshot?.data();
    final displayName = _firstNonEmptyString([
      data?['name'],
      data?['fullName'],
      FirebaseAuth.instance.currentUser?.displayName,
    ], 'You');
    final location = _userLocationText(snapshot);
    final recordData = <String, dynamic>{
      'name': displayName,
      'address': location,
      'type': 'device',
      'lat': data?['deviceLat'] ?? data?['currentLat'],
      'lng': data?['deviceLng'] ?? data?['currentLng'],
    };
    final display = _AddressDisplayEntry(
      primary: '$displayName | You',
      secondary: location,
    );
    return _AddressRecord(display: display, data: recordData);
  }

  List<_AddressRecord> _buildAddressRecords(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final records = <_AddressRecord>[];
    records.add(_userAddressRecord(snapshot));
    final extra = _extractAddressList(snapshot?.data());
    for (final entry in extra) {
      records.add(
        _AddressRecord(display: _addressEntryToDisplay(entry), data: entry),
      );
    }
    return records;
  }

  _AddressDisplayEntry _addressEntryToDisplay(Map<String, dynamic> entry) {
    final name = _addressNameText(entry);
    final label = _addressLabelOnly(entry);
    final secondary = _addressLineText(entry);
    final primary = label.isNotEmpty ? '$name | $label' : name;
    return _AddressDisplayEntry(primary: primary, secondary: secondary);
  }

  String _userLocationText(DocumentSnapshot<Map<String, dynamic>>? snapshot) {
    final data = snapshot?.data();
    return _firstNonEmptyString([
      data?['deviceLocation'],
      data?['currentLocation'],
      data?['currentLocationName'],
      data?['locationName'],
      data?['location'],
    ], 'Location unavailable');
  }

  _AddressRecord? _getSelectedRecord() {
    if (_addressRecords.isEmpty) return null;
    final index = math.min(_selectedAddressIndex, _addressRecords.length - 1);
    return _addressRecords[index];
  }

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() => setState(() {}));
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onHoldComplete();
      }
    });

    final entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryController = entryController;
    _entryFade = CurvedAnimation(
      parent: entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: entryController, curve: Curves.easeOutCubic),
        );

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasActive) {
        _entryController?.forward(from: 0);
      } else {
        _entryController?.value = 1;
      }
    });
  }

  @override
  void didUpdateWidget(covariant SosActivateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _entryController?.forward(from: 0);
    }
    _wasActive = isActive;
  }

  @override
  void dispose() {
    _hideAddressDropdown();
    _holdController.dispose();
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
    super.dispose();
  }

  void _onHoldStart() {
    if (_isTriggering) return;
    setState(() => _isHolding = true);
    _holdController.forward(from: 0);
  }

  void _onHoldCancel() {
    if (!_isHolding || _isTriggering) return;
    _holdController.reset();
    setState(() => _isHolding = false);
  }

  void _onHoldComplete() {
    setState(() {
      _isHolding = false;
    });
    _triggerSosFlow();
  }

  Future<void> _triggerSosFlow() async {
    if (_isTriggering) return;
    final record = _getSelectedRecord();
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to capture your address.')),
      );
      return;
    }
    setState(() => _isTriggering = true);
    try {
      final sosId = await _createSosRequest(record);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SOS alert broadcasted')));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SosFindingScreen(sosId: sosId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to raise SOS: $e')));
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  Future<String> _createSosRequest(_AddressRecord record) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'You must be signed in to call help.';
    }
    final now = DateTime.now();
    final reason = _sosReasons[_selectedReasonIndex];
    final data = <String, dynamic>{
      'userId': user.uid,
      'userName': user.displayName ?? 'You',
      'addressLabel': record.display.primary,
      'address': record.display.secondary,
      'addressMeta': record.data,
      'reason': reason,
      'status': 'SEARCHING',
      'tracking': [
        {
          'label': 'SOS activated',
          'description': reason,
          'timestamp': now.toIso8601String(),
          'status': 'REQUESTED',
        },
      ],
      'createdAt': FieldValue.serverTimestamp(),
    };
    final lat = _toDouble(
      record.data['lat'] ?? record.data['latitude'] ?? record.data['deviceLat'],
    );
    final lng = _toDouble(
      record.data['lng'] ??
          record.data['longitude'] ??
          record.data['deviceLng'],
    );
    if (lat != null && lng != null) {
      data['userLat'] = lat;
      data['userLng'] = lng;
    }
    final doc = await FirebaseFirestore.instance.collection('sos').add(data);
    return doc.id;
  }

  double? _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Future<void> _showAddressMenu(
    BuildContext context,
    List<_AddressRecord> records,
  ) async {
    if (records.isEmpty) return;
    _hideAddressDropdown();
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final renderBox = renderObject;
    final position = renderBox.localToGlobal(Offset.zero);
    final width = renderBox.size.width;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideAddressDropdown,
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + renderBox.size.height + 6,
              width: width,
              child: Theme(
                data: Theme.of(overlayContext).copyWith(
                  splashFactory: NoSplash.splashFactory,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  canvasColor: Colors.white,
                  scaffoldBackgroundColor: Colors.white,
                  textSelectionTheme: const TextSelectionThemeData(
                    selectionColor: Colors.transparent,
                    selectionHandleColor: Colors.transparent,
                  ),
                  dialogTheme: DialogThemeData(backgroundColor: Colors.white),
                ),
                child: _buildDropdownList(overlayContext, records),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
    _addressDropdownEntry = entry;
  }

  void _hideAddressDropdown() {
    _addressDropdownEntry?.remove();
    _addressDropdownEntry = null;
  }

  Widget _buildDropdownList(
    BuildContext context,
    List<_AddressRecord> records,
  ) {
    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(
          height: math.min(records.length * 58.0, 240),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final selected = index == _selectedAddressIndex;
            final record = records[index];
            final textTheme = Theme.of(context).textTheme;
            final primaryStyle =
                textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _sosHeadingColor,
                ) ??
                _addressDropdownPrimaryStyle;
            final secondaryStyle =
                textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: _sosSubTextColor,
                ) ??
                _addressDropdownSecondaryStyle;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _selectedAddressIndex = index);
                _hideAddressDropdown();
              },
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? Colors.grey[400]! : Colors.grey[200]!,
                  ),
                  color: selected ? Colors.grey[100] : Colors.white,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            record.display.primary,
                            style: primaryStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            record.display.secondary,
                            style: secondaryStyle,
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
    );
  }

  Widget _buildAddressHeader(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream(),
      builder: (context, snapshot) {
        final records = _buildAddressRecords(snapshot.data);
        if (records.isEmpty) {
          return const _PremiumCard(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        _addressRecords = records;
        final selectedIndex = math.min(
          _selectedAddressIndex,
          records.length - 1,
        );
        final current = records[selectedIndex];
        return _PremiumCard(
          padding: EdgeInsets.zero,
          child: Builder(
            builder: (headerContext) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(_cardRadius),
                  onTap: () => _showAddressMenu(headerContext, records),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: _accentGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.display.primary,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _sosHeadingColor,
                                  fontSize: 13,
                                  letterSpacing: -0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                current.display.secondary,
                                style: const TextStyle(
                                  color: _sosSubTextColor,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildReasonChips(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_sosReasons.length, (index) {
              final reason = _sosReasons[index];
              final selected = index == _selectedReasonIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedReasonIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    constraints: const BoxConstraints(minHeight: 26),
                    decoration: BoxDecoration(
                      color: selected ? _accentGreen : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? _accentGreen.withValues(alpha: 0.45)
                            : _reasonChipBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        reason,
                        style: selected
                            ? _reasonChipBaseStyle.copyWith(color: Colors.white)
                            : _reasonChipBaseStyle.copyWith(
                                color: _sosHeadingColor,
                              ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildHoldButton(BuildContext context) {
    final circleSize = 152.0;
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: circleSize,
          height: circleSize,
          child: CircularProgressIndicator(
            value: _holdController.value,
            strokeWidth: 10,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
              theme.colorScheme.error.withValues(alpha: 0.9),
            ),
          ),
        ),
        GestureDetector(
          onTapDown: (_) => _onHoldStart(),
          onTapCancel: _onHoldCancel,
          onTapUp: (_) => _onHoldCancel(),
          behavior: HitTestBehavior.opaque,
            child: Container(
              width: circleSize - 40,
              height: circleSize - 40,
              decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.error,
                  theme.colorScheme.error.withValues(alpha: 0.8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.error.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Center(
              child: _isTriggering
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    )
                  : Icon(
                      _isHolding ? Icons.favorite : Icons.notifications_active,
                      color: Colors.white,
                      size: 42,
                    ),
            ),
          ),
        ),
        if (!_isHolding && !_isTriggering)
          Positioned(
            bottom: -24,
            child: Text(
              'Hold for 5 seconds',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _sosSubTextColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _sosHeadingColor,
        letterSpacing: -0.1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
    final entrySlide =
        _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);

    return FadeTransition(
      opacity: entryFade,
      child: SlideTransition(
        position: entrySlide,
        child: Scaffold(
          backgroundColor: _pageBackground,
          appBar: buildProfileStyleAppBar(title: 'Emergency Assistance'),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    kScreenHorizontalPaddingValue,
                    16,
                    kScreenHorizontalPaddingValue,
                    18,
                  ),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _PremiumCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _accentGreen.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _accentGreen.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.sos_rounded,
                              size: 20,
                              color: _accentGreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Need help now?',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _sosHeadingColor,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Choose your location and why you need support before activating SOS.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _sosSubTextColor,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionHeader('Location'),
                    const SizedBox(height: 10),
                    _buildAddressHeader(context),
                    const SizedBox(height: 16),
                    _buildSectionHeader('Reason'),
                    const SizedBox(height: 10),
                    _buildReasonChips(context),
                    const SizedBox(height: 16),
                    _PremiumCard(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      child: Column(
                        children: [
                          Center(child: _buildHoldButton(context)),
                          const SizedBox(height: 12),
                          Text(
                            'Once helpers accept your alert we will guide them to your selected address.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _sosSubTextColor,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AddressRecord {
  const _AddressRecord({required this.display, required this.data});

  final _AddressDisplayEntry display;
  final Map<String, dynamic> data;
}

class _AddressDisplayEntry {
  const _AddressDisplayEntry({required this.primary, required this.secondary});

  final String primary;
  final String secondary;
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
