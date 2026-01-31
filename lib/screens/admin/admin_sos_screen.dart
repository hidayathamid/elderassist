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

import 'admin_ui.dart';
import 'admin_sos_details_sheet.dart';
import '../../ui_tokens.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_screen.dart'
    show activityAccentBlue, activityBackgroundColor, activityPrimaryTextColor;

const Color _primaryBlue = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

const double _heroHeight = 220.0;
const double _headerCardOverlap = 96.0;
const double _panelMaxExtent = 0.96;

const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];

const TextStyle _sosTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
const TextStyle _sosFileStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: _profileDarkText60,
);
const TextStyle _actionLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);

final DateFormat _sosDateFormat = DateFormat('MMM d, yyyy');

Widget _buildActivityStyleEmptyState(
  IconData icon,
  String title,
  String subtitle,
) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: activityAccentBlue),
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

class AdminSosScreen extends StatelessWidget {
  const AdminSosScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 2,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: tabIndex,
      child: const _AdminSosDashboard(),
    );
  }
}

class _AdminSosDashboard extends StatefulWidget {
  const _AdminSosDashboard();

  @override
  State<_AdminSosDashboard> createState() => _AdminSosDashboardState();
}

class _AdminSosDashboardState extends State<_AdminSosDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  late DateTime _selectedMonth;
  final TextEditingController _searchController = TextEditingController();

  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;

  String _searchText = '';
  _SosStatusFilter _statusFilter = _SosStatusFilter.all;
  bool _modalSheetScrimVisible = false;

  @override
  void initState() {
    super.initState();
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
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _panelController.dispose();
    _panelScrollController.dispose();
    _searchController.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    final value = _searchController.text.trim();
    setState(() => _searchText = value);
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
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  void _setStatusFilter(_SosStatusFilter filter) {
    if (_statusFilter == filter) return;
    setState(() => _statusFilter = filter);
  }

  Future<void> _generateMonthlySosReport() async {
    final month = _selectedMonth;
    const pdfType = XTypeGroup(label: 'pdf', extensions: ['pdf']);

    BuildContext? loadingDialogContext;
    var loadingOpen = true;

    void closeLoadingIfOpen() {
      if (!loadingOpen) return;
      final ctx = loadingDialogContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.pop();
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
                    'Generating report...',
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
      final callable = _functions.httpsCallable('generateAdminSosReport');
      final result = await callable.call(<String, dynamic>{
        'year': month.year,
        'month': month.month,
      });

      closeLoadingIfOpen();

      final data = (result.data as Map).cast<String, dynamic>();
      final pdfBase64 = (data['pdfBase64'] as String?) ?? '';
      final fileName = (data['fileName'] as String?) ?? 'sos-report.pdf';
      if (pdfBase64.trim().isEmpty) return;

      final bytes = base64Decode(pdfBase64);

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
        final tmpDir = await getTemporaryDirectory();
        final path = '${tmpDir.path}/$fileName';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);

        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                          await Share.shareXFiles(
                            [XFile(path, mimeType: 'application/pdf', name: fileName)],
                            subject: fileName,
                          );
                        } catch (_) {}
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
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
                          await OpenFilex.open(path);
                        } catch (_) {}
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
    } catch (_) {
      closeLoadingIfOpen();
    }
  }

  Future<void> _openSosDetailsSheet(
    BuildContext context,
    _AdminSosEntry entry,
  ) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => AdminSosDetailsSheet(sosId: entry.id),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _openSosEditSheet(
    BuildContext context,
    _AdminSosEntry entry,
  ) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => AdminSosEditSheet(sosId: entry.id),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _confirmDeleteSos(
    BuildContext context,
    _AdminSosEntry entry,
  ) async {
    final ref = FirebaseFirestore.instance.collection('sos').doc(entry.id);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Delete SOS?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'This will remove SOS ${entry.id} from Firestore.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    try {
      await ref.delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final range = _monthRange(_selectedMonth);
    final startTs = Timestamp.fromDate(range.start);
    final endTs = Timestamp.fromDate(range.end);

    final sosStream = _db
        .collection('sos')
        .where('createdAt', isGreaterThanOrEqualTo: startTs)
        .where('createdAt', isLessThan: endTs)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    final totalCountStream = sosStream.map((snap) => snap.size).distinct();
    final resolvedCountStream = sosStream.map((snap) {
      var count = 0;
      for (final doc in snap.docs) {
        final status = (doc.data()['status'] as String?) ?? '';
        final normalized = status.trim().toUpperCase();
        if (normalized == 'RESOLVED' || normalized == 'COMPLETED') count++;
      }
      return count;
    }).distinct();

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
            child: _MonthlySosAnalyticsCard(
              monthLabel: _monthLabel(_selectedMonth),
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onGenerateReport: _generateMonthlySosReport,
              totalCountStream: totalCountStream,
              resolvedCountStream: resolvedCountStream,
            ),
          ),
        ],
      ),
    );

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final scrimTopInset =
        MediaQuery.of(context).padding.top + kToolbarHeight;
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
        Positioned(
          top: scrimTopInset,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              opacity: _modalSheetScrimVisible ? 1 : 0,
              child: ColoredBox(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.54)),
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

            final extentBase = panelMinExtent + (denom * _panelController.value);
            final t = denom <= 0 ? 0.0 : _panelController.value;
            final appBarT =
                ((extentBase - 0.90) / 0.10).clamp(0.0, 1.0).toDouble();
            final topChromeInset =
                (lerpDouble(0, kToolbarHeight + 6.0, appBarT) ?? 0.0)
                    .clamp(0.0, double.infinity);

            final panelHeight =
                (extentBase * screenHeight).clamp(0.0, screenHeight).toDouble();
            final dragRangePx =
                (denom.abs() * screenHeight).clamp(1.0, double.infinity).toDouble();

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
                        alpha: (lerpDouble(0.05, 0.07, t) ?? 0.06).clamp(0.0, 1.0),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (lerpDouble(0.14, 0.22, t) ?? 0.14).clamp(0.0, 1.0),
                        ),
                        blurRadius: (lerpDouble(18, 26, t) ?? 22).clamp(
                          0.0,
                          double.infinity,
                        ),
                        offset: Offset(
                          0,
                          -((lerpDouble(6, 10, t) ?? 8).clamp(0.0, double.infinity)),
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
                        onVerticalDragUpdate: (details) => _onPanelHandleDragUpdate(
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
                      Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: sosStream,
                          builder: (context, snapshot) {
                            return ListView(
                              controller: _panelScrollController,
                              padding: EdgeInsets.only(
                                bottom: (bottomInset + 24).clamp(24.0, 64.0),
                              ),
                              physics: const ClampingScrollPhysics(),
                              children: [
                                _SosSearchField(controller: _searchController),
                                const SizedBox(height: 10),
                                _SosFilterBar(
                                  selected: _statusFilter,
                                  onSelected: _setStatusFilter,
                                ),
                                Transform.translate(
                                  offset: const Offset(0, -60),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: _SosListBody(
                                      searchText: _searchText,
                                      snapshot: snapshot,
                                      statusFilter: _statusFilter,
                                      onViewEntry: (entry) =>
                                          _openSosDetailsSheet(context, entry),
                                      onEditEntry: (entry) =>
                                          _openSosEditSheet(context, entry),
                                      onDeleteEntry: (entry) =>
                                          _confirmDeleteSos(context, entry),
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
            );
          },
        ),
      ],
    );

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: buildProfileStyleAppBar(title: 'SOS'),
      body: content,
    );
  }
}

class _SosSearchField extends StatelessWidget {
  const _SosSearchField({required this.controller});

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
        hintText: 'Search SOS',
        hintStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.35),
        ),
        prefixIcon: const Icon(Icons.search, size: 16, color: _primaryBlue),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}

enum _SosStatusFilter { all, active, resolved }

class _SosFilterBar extends StatelessWidget {
  const _SosFilterBar({required this.selected, required this.onSelected});

  final _SosStatusFilter selected;
  final ValueChanged<_SosStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _SosStatusFilter.active
        ? 'Active SOS'
        : selected == _SosStatusFilter.resolved
        ? 'Resolved SOS'
        : 'All SOS';

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
                    selected: selected == _SosStatusFilter.all,
                    onTap: () => onSelected(_SosStatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Active',
                    selected: selected == _SosStatusFilter.active,
                    onTap: () => onSelected(_SosStatusFilter.active),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Resolved',
                    selected: selected == _SosStatusFilter.resolved,
                    onTap: () => onSelected(_SosStatusFilter.resolved),
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

class _AdminSosEntry {
  const _AdminSosEntry({
    required this.id,
    required this.status,
    required this.userId,
    required this.userName,
    required this.selectedPersonName,
    required this.address,
    required this.reason,
    required this.createdAt,
    required this.caregiverId,
    required this.caregiverName,
    required this.bookingId,
  });

  final String id;
  final String status;
  final String userId;
  final String userName;
  final String selectedPersonName;
  final String address;
  final String reason;
  final Timestamp? createdAt;
  final String caregiverId;
  final String caregiverName;
  final String bookingId;

  static String _pickText(Object? value) => (value?.toString() ?? '').trim();

  static _AdminSosEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final status = _pickText(data['status']).toUpperCase();
    final userId = _pickText(data['userId']);
    final userName = _pickText(data['userName']);
    final selectedPersonName = _pickText(data['selectedPersonName']);
    final address = _pickText(
      data['address'] ?? data['userAddress'] ?? data['personAddress'],
    );
    final reason = _pickText(data['reason']);
    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is Timestamp ? createdAtRaw : null;
    final caregiverId = _pickText(data['caregiverId']);
    final caregiverName = _pickText(data['caregiverName']);
    final bookingId = _pickText(data['bookingId']);
    return _AdminSosEntry(
      id: doc.id,
      status: status.isNotEmpty ? status : 'UNKNOWN',
      userId: userId,
      userName: userName,
      selectedPersonName: selectedPersonName,
      address: address,
      reason: reason,
      createdAt: createdAt,
      caregiverId: caregiverId,
      caregiverName: caregiverName,
      bookingId: bookingId,
    );
  }
}

class _SosListBody extends StatelessWidget {
  const _SosListBody({
    required this.searchText,
    required this.snapshot,
    required this.statusFilter,
    required this.onViewEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final String searchText;
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot;
  final _SosStatusFilter statusFilter;
  final ValueChanged<_AdminSosEntry> onViewEntry;
  final ValueChanged<_AdminSosEntry> onEditEntry;
  final ValueChanged<_AdminSosEntry> onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return SizedBox(
        height: 320,
        child: _buildActivityStyleEmptyState(
          Icons.sos_outlined,
          'Unable to load SOS',
          'Please try again.',
        ),
      );
    }
    if (!snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final entries = snapshot.data!.docs.map(_AdminSosEntry.fromDoc).toList();
    final q = searchText.trim().toLowerCase();

    final filtered = entries.where((e) {
      if (q.isEmpty) return true;
      if (e.id.toLowerCase().contains(q)) return true;
      if (e.status.toLowerCase().contains(q)) return true;
      if (e.userName.toLowerCase().contains(q)) return true;
      if (e.selectedPersonName.toLowerCase().contains(q)) return true;
      if (e.address.toLowerCase().contains(q)) return true;
      return false;
    }).toList()
      ..sort((a, b) {
        final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

    final statusFiltered = filtered.where((e) {
      if (statusFilter == _SosStatusFilter.all) return true;
      final normalized = e.status.trim().toUpperCase();
      if (statusFilter == _SosStatusFilter.resolved) {
        return normalized == 'RESOLVED' || normalized == 'COMPLETED';
      }
      return normalized != 'RESOLVED' && normalized != 'COMPLETED';
    }).toList(growable: false);

    if (statusFiltered.isEmpty) {
      return SizedBox(
        height: 320,
        child: _buildActivityStyleEmptyState(
          Icons.search_off_outlined,
          'No results',
          'Try a different keyword.',
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: statusFiltered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _AdminSosCard(
          indexNumber: index + 1,
          entry: statusFiltered[index],
          onView: () => onViewEntry(statusFiltered[index]),
          onEdit: () => onEditEntry(statusFiltered[index]),
          onDelete: () => onDeleteEntry(statusFiltered[index]),
        );
      },
    );
  }
}

class _AdminSosCard extends StatelessWidget {
  const _AdminSosCard({
    required this.indexNumber,
    required this.entry,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final int indexNumber;
  final _AdminSosEntry entry;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final caregiverName = entry.caregiverName.trim().isNotEmpty
        ? entry.caregiverName.trim()
        : (entry.userName.trim().isNotEmpty ? entry.userName.trim() : 'SOS');
    final fileLabel = entry.reason.trim().isNotEmpty
        ? entry.reason.trim()
        : (entry.selectedPersonName.trim().isNotEmpty
              ? entry.selectedPersonName.trim()
              : 'SOS alert');
    final address = entry.address.trim();
    final createdAt = entry.createdAt?.toDate();
    final dateLabel = createdAt != null
        ? 'Created: ${_sosDateFormat.format(createdAt)}'
        : 'Created: unknown';
    final bookingId = entry.bookingId.trim();
    final caregiverId = entry.caregiverId.trim();
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);
    final normalizedStatus = entry.status.trim().toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: Colors.grey.shade300, width: 1.1),
        boxShadow: _cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: caregiverRef?.get(),
                builder: (context, snapshot) {
                  final caregiverData = snapshot.data?.data();
                    final resolvedName =
                        (caregiverData?['name'] as String?)?.trim() ??
                        caregiverName;
                    final caregiverPhoto =
                        (caregiverData?['profile_photo'] as String?)?.trim() ??
                        (caregiverData?['photoUrl'] as String?)?.trim();

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            DefaultProfileAvatar(
                              radius: 22,
                              photoUrl: caregiverPhoto?.isNotEmpty == true
                                  ? caregiverPhoto
                                  : null,
                              label: resolvedName.isNotEmpty
                                  ? resolvedName
                                  : '?',
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
                                      resolvedName.isNotEmpty
                                          ? resolvedName
                                          : 'Caregiver',
                                      style: _sosTitleStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            PopupMenuButton<String>(
                              tooltip: 'Change status',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                      ),
                                    ),
                                    onSelected: (value) async {
                                      final ref = FirebaseFirestore.instance
                                          .collection('sos')
                                          .doc(entry.id);
                                      try {
                                        await ref.update({'status': value});
                                      } catch (_) {}
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'ACTIVE',
                                        child: Row(
                                          children: [
                                            const Text(
                                              'Active',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (normalizedStatus == 'ACTIVE')
                                              const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'RESOLVED',
                                        child: Row(
                                          children: [
                                            const Text(
                                              'Resolved',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (normalizedStatus ==
                                                    'RESOLVED' ||
                                                normalizedStatus == 'COMPLETED')
                                              const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                              child: _SosStatusMenuChip(
                                status: normalizedStatus,
                              ),
                            ),
                          ],
                        ),
                            ],
                          ),
                        ),
                      ],
                    );
                },
              ),
              const SizedBox(height: UiTokens.s10),
              Container(
                height: 1.2,
                color: Colors.black.withValues(alpha: 0.06),
              ),
              if (fileLabel.trim().isNotEmpty)
                _SosCardInfoRow(label: 'Alert', value: fileLabel.trim()),
              _SosCardInfoRow(label: 'SOS ID', value: entry.id),
              _SosCardInfoRow(label: 'Status', value: entry.status),
              if (address.isNotEmpty)
                _SosCardInfoRow(label: 'Address', value: address),
              if (bookingId.isNotEmpty)
                _SosCardInfoRow(label: 'Booking ID', value: bookingId),
              _SosCardInfoRow(
                label: 'Date',
                value: dateLabel,
                showBorder: false,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
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
              Row(
                children: [
                  Expanded(
                    child: _SosActionButton(
                      icon: Icons.remove_red_eye,
                      label: 'View',
                      onTap: onView,
                      primary: true,
                    ),
                  ),
                  const SizedBox(width: UiTokens.s8),
                  Expanded(
                    child: _SosActionButton(
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

class _SosActionButton extends StatelessWidget {
  const _SosActionButton({
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
            Text(label, style: _actionLabelStyle.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

class _SosStatusMenuChip extends StatelessWidget {
  const _SosStatusMenuChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toUpperCase();
    final isResolved = normalized == 'RESOLVED' || normalized == 'COMPLETED';
    final label = isResolved ? 'Resolved' : 'Active';
    final dotColor = isResolved ? Colors.green.shade700 : _primaryBlue;

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
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
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

class _MonthlySosAnalyticsCard extends StatelessWidget {
  const _MonthlySosAnalyticsCard({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.totalCountStream,
    required this.resolvedCountStream,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Stream<int> totalCountStream;
  final Stream<int> resolvedCountStream;

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
        stream: totalCountStream,
        builder: (context, totalSnap) {
          return StreamBuilder<int>(
            stream: resolvedCountStream,
            builder: (context, resolvedSnap) {
              final total = totalSnap.data ?? 0;
              final resolved = resolvedSnap.data ?? 0;
              final active = math.max(0, total - resolved);

              final segments = <_DonutSegment>[
                _DonutSegment(
                  label: 'Active',
                  count: active,
                  color: adminAccentGold,
                ),
                _DonutSegment(
                  label: 'Resolved',
                  count: resolved,
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
                                label: 'Total SOS',
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
                              if (s.label == 'Resolved')
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
                                      style: TextStyle(fontWeight: FontWeight.w700),
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
              const Text(
                'items',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.total, required this.segments});

  final int total;
  final List<_DonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.08);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - stroke / 2),
      0,
      math.pi * 2,
      false,
      backgroundPaint,
    );

    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.count <= 0) continue;
      final sweep = (segment.count / total) * math.pi * 2;
      paint.color = segment.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.segments != segments;
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _profileDarkText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _profileDarkText,
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _SosDetailsSheet extends StatelessWidget {
  const _SosDetailsSheet({required this.entry});

  final _AdminSosEntry entry;

  Widget _cardShell({required Widget child}) {
    return Container(
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
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: _profileDarkText,
        ),
      ),
    );
  }

  static String _labelValue(String value) {
    final v = value.trim();
    return v.isNotEmpty ? v : '-';
  }

  static String _timeLabel(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;

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
                  const SizedBox(height: 10),
                  _cardShell(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(label: 'SOS ID', value: _labelValue(entry.id)),
                          const SizedBox(height: 8),
                          _InfoRow(label: 'Status', value: _labelValue(entry.status)),
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: 'Created at',
                            value: _timeLabel(entry.createdAt),
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(label: 'Reason', value: _labelValue(entry.reason)),
                          const SizedBox(height: 8),
                          _InfoRow(label: 'Address', value: _labelValue(entry.address)),
                          if (entry.bookingId.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _InfoRow(
                              label: 'Booking ID',
                              value: _labelValue(entry.bookingId),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('Caregiver'),
                  _PersonCard(
                    roleLabel: 'Caregiver',
                    docStream: entry.caregiverId.trim().isEmpty
                        ? null
                        : FirebaseFirestore.instance
                            .collection('caregivers')
                            .doc(entry.caregiverId.trim())
                            .snapshots(),
                    fallbackName: entry.caregiverName,
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('Owner'),
                  _PersonCard(
                    roleLabel: 'Client',
                    docStream: entry.userId.trim().isEmpty
                        ? null
                        : FirebaseFirestore.instance
                            .collection('users')
                            .doc(entry.userId.trim())
                            .snapshots(),
                    fallbackName:
                        entry.userName.isNotEmpty ? entry.userName : entry.userId,
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('Selected person'),
                  _SelectedPersonCard(
                    name: entry.selectedPersonName.isNotEmpty
                        ? entry.selectedPersonName
                        : entry.userName,
                    label: '',
                    address: entry.address,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            value,
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

class _SosCardInfoRow extends StatelessWidget {
  const _SosCardInfoRow({
    required this.label,
    required this.value,
    this.showBorder = true,
  });

  final String label;
  final String value;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showBorder
              ? Border(
                  bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
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
                  value.trim().isEmpty ? 'Unavailable' : value.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _profileDarkText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.roleLabel,
    required this.docStream,
    required this.fallbackName,
  });

  final String roleLabel;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? docStream;
  final String fallbackName;

  static String _pickText(Object? value) => (value?.toString() ?? '').trim();

  static String? _pickPhoto(Map<String, dynamic> data) {
    return _pickText(data['photoUrl']).isNotEmpty
        ? _pickText(data['photoUrl'])
        : (_pickText(data['avatarUrl']).isNotEmpty
            ? _pickText(data['avatarUrl'])
            : (_pickText(data['imageUrl']).isNotEmpty
                ? _pickText(data['imageUrl'])
                : null));
  }

  Widget _shell({required Widget child}) {
    return Container(
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
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = docStream;
    if (stream == null) {
      return _shell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: _InfoRow(
            label: roleLabel,
            value: fallbackName.isNotEmpty ? fallbackName : '-',
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = _pickText(data['name']);
        final phone = _pickText(data['phone']);
        final address = _pickText(data['defaultAddress']);
        final photo = _pickPhoto(data);

        return _shell(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DefaultProfileAvatar(
                  radius: 22,
                  photoUrl: photo,
                  label: name.isNotEmpty ? name : fallbackName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : fallbackName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _profileDarkText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        roleLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            phone,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectedPersonCard extends StatelessWidget {
  const _SelectedPersonCard({
    required this.name,
    required this.label,
    required this.address,
  });

  final String name;
  final String label;
  final String address;

  Widget _shell({required Widget child}) {
    return Container(
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
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isNotEmpty ? name.trim() : '-';
    final displayLabel = label.trim();
    final displayAddress = address.trim();

    return _shell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DefaultProfileAvatar(
              radius: 22,
              photoUrl: null,
              label: displayName,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _profileDarkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (displayLabel.isNotEmpty)
                    Text(
                      displayLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (displayAddress.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayAddress,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
