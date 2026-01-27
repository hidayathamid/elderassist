import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/default_profile_avatar.dart';
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
    'Caregiver details',
    'Client details',
    'SOS details',
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
          photoUrl: (photoUrl?.trim().isNotEmpty == true) ? photoUrl!.trim() : null,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  Widget _buildCaregiverTab(Map<String, dynamic> sos) {
    final caregiverId = _text(sos['caregiverId']);
    final caregiverName = _text(sos['caregiverName']);
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef?.snapshots(),
      builder: (context, snap) {
        final caregiver = snap.data?.data() ?? const <String, dynamic>{};
        final name = _valueOrUnavailable(
          _text(caregiver['name']).isNotEmpty ? _text(caregiver['name']) : caregiverName,
        );
        final phone = _valueOrUnavailable(
          _text(caregiver['phone']).isNotEmpty
              ? _text(caregiver['phone'])
              : _text(caregiver['phoneNumber']),
        );
        final address = _valueOrUnavailable(
          _text(caregiver['defaultAddress']).isNotEmpty
              ? _text(caregiver['defaultAddress'])
              : _text(caregiver['address']),
        );
        final service = _valueOrUnavailable(_text(sos['service']));
        final photoUrl = _text(caregiver['profile_photo']).isNotEmpty
            ? _text(caregiver['profile_photo'])
            : _text(caregiver['photoUrl']).isNotEmpty
                  ? _text(caregiver['photoUrl'])
                  : _text(caregiver['imageUrl']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Caregiver'),
            const SizedBox(height: 4),
            _centerAvatar(name, photoUrl.isNotEmpty ? photoUrl : null),
            _buildTabContent([
              _buildInfoRow(icon: Icons.person, title: 'Caregiver name', value: name),
              _buildInfoRow(
                icon: Icons.medical_services_outlined,
                title: 'Services',
                value: service,
              ),
              _buildInfoRow(icon: Icons.phone_android, title: 'Contact', value: phone),
              _buildInfoRow(
                icon: Icons.home,
                title: 'Address',
                value: address,
                showBorder: false,
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
        final name = _valueOrUnavailable(
          _text(user['name']).isNotEmpty ? _text(user['name']) : userName,
        );
        final phone = _valueOrUnavailable(_text(user['phone']));
        final address = _valueOrUnavailable(
          _text(user['defaultAddress']).isNotEmpty
              ? _text(user['defaultAddress'])
              : _text(user['address']),
        );
        final photoUrl = _text(user['profile_photo']).isNotEmpty
            ? _text(user['profile_photo'])
            : _text(user['photoUrl']).isNotEmpty
                  ? _text(user['photoUrl'])
                  : _text(user['imageUrl']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Client'),
            const SizedBox(height: 4),
            _centerAvatar(name, photoUrl.isNotEmpty ? photoUrl : null),
            _buildTabContent([
              _buildInfoRow(icon: Icons.person, title: 'Client name', value: name),
              _buildInfoRow(icon: Icons.phone_android, title: 'Contact', value: phone),
              _buildInfoRow(
                icon: Icons.home,
                title: 'Address',
                value: address,
                showBorder: false,
              ),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildSosTab(Map<String, dynamic> sos) {
    final sosId = widget.sosId;
    final status = _valueOrUnavailable(_text(sos['status']));
    final createdAt = _timeLabel(sos['createdAt']);
    final reason = _valueOrUnavailable(_text(sos['reason']));
    final address = _valueOrUnavailable(_text(sos['address']));
    final bookingId = _text(sos['bookingId']);
    final selectedPersonName = _valueOrUnavailable(_text(sos['selectedPersonName']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'SOS details'),
        _buildTabContent([
          _buildInfoRow(icon: Icons.sos_outlined, title: 'SOS ID', value: sosId),
          _buildInfoRow(icon: Icons.flag_outlined, title: 'Status', value: status),
          _buildInfoRow(icon: Icons.access_time, title: 'Created at', value: createdAt),
          _buildInfoRow(icon: Icons.report_outlined, title: 'Reason', value: reason),
          _buildInfoRow(icon: Icons.home, title: 'Address', value: address),
          _buildInfoRow(
            icon: Icons.person,
            title: 'Selected person',
            value: selectedPersonName,
            showBorder: bookingId.isNotEmpty,
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
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sosRef = FirebaseFirestore.instance.collection('sos').doc(widget.sosId);

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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: sosRef.snapshots(),
                builder: (context, snap) {
                  final sos = snap.data?.data() ?? const <String, dynamic>{};
                  Widget tabContent() {
                    final idx = _selectedTabIndex.clamp(0, labels.length - 1);
                    if (idx == 0) return _buildCaregiverTab(sos);
                    if (idx == 1) return _buildClientTab(sos);
                    return _buildSosTab(sos);
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
      _statusCtrl.text = _text(data['status']).isNotEmpty ? _text(data['status']) : 'ACTIVE';
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
    final box = _statusFieldKey.currentContext?.findRenderObject() as RenderBox?;
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
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      await FirebaseFirestore.instance.collection('sos').doc(widget.sosId).update({
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
        : FirebaseFirestore.instance.collection('caregivers').doc(_caregiverId.trim());

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
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                            (caregiverData?['profile_photo'] as String?)?.trim() ??
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
