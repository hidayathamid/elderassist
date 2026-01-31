import 'dart:ui' show lerpDouble;
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_tokens.dart';
import '../../widgets/default_profile_avatar.dart';
import '../user/activity/activity_screen.dart'
    show
        activityBackgroundColor,
        activityButtonYellow,
        activityPrimaryTextColor;
import '../../widgets/standard_app_bar.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _primaryBlue = Color(0xFF00A8A7);

const double _heroHeight = 220.0;
const double _headerCardOverlap = 96.0;
const double _panelMaxExtent = 0.96;

const TextStyle _documentTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
const TextStyle _documentFileStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: _profileDarkText60,
);
const TextStyle _documentMetaStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: _profileDarkText60,
);
const TextStyle _actionLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);

const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];

final DateFormat _docDateFormat = DateFormat('MMM d, yyyy');

const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);

String _string(dynamic value) => value?.toString().trim() ?? '';

String _pickName(Map<String, dynamic>? data) {
  if (data == null) return '';
  final name = _string(data['name']);
  if (name.isNotEmpty) return name;
  final fullName = _string(data['fullName']);
  if (fullName.isNotEmpty) return fullName;
  final userName = _string(data['userName']);
  if (userName.isNotEmpty) return userName;
  final displayName = _string(data['displayName']);
  if (displayName.isNotEmpty) return displayName;
  return '';
}

String _pickPhotoUrl(Map<String, dynamic>? data) {
  if (data == null) return '';
  final profilePhoto = _string(data['profile_photo']);
  if (profilePhoto.isNotEmpty) return profilePhoto;
  final photoUrl = _string(data['photoUrl']);
  if (photoUrl.isNotEmpty) return photoUrl;
  return '';
}

Future<Map<String, dynamic>?> _loadCaregiverProfile(String caregiverId) async {
  final uid = caregiverId.trim();
  if (uid.isEmpty) return null;
  final db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> tryCollection(String collection) async {
    final snap = await db.collection(collection).doc(uid).get();
    return snap.data();
  }

  final caregiver = await tryCollection('caregivers');
  if (caregiver != null) return caregiver;

  final waiting = await tryCollection('waitinglist');
  if (waiting != null) return waiting;

  final user = await tryCollection('users');
  return user;
}

class AdminDocumentsScreen extends StatefulWidget {
  const AdminDocumentsScreen({super.key});

  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  late DateTime _selectedMonth;
  _DocumentsStatusFilter _statusFilter = _DocumentsStatusFilter.all;
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
    setState(() => _searchText = _searchController.text.trim());
  }

  void _setStatusFilter(_DocumentsStatusFilter filter) {
    if (_statusFilter == filter) return;
    setState(() => _statusFilter = filter);
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

  Future<void> _generateMonthlyDocumentsReport() async {
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
      final callable = _functions.httpsCallable('generateAdminDocumentsReport');
      final result = await callable.call(<String, dynamic>{
        'year': month.year,
        'month': month.month,
      });

      closeLoadingIfOpen();

      final data = (result.data as Map).cast<String, dynamic>();
      final pdfBase64 = (data['pdfBase64'] as String?) ?? '';
      final fileName = (data['fileName'] as String?) ?? 'documents-report.pdf';
      if (pdfBase64.trim().isEmpty) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Missing PDF data from server',
        );
      }

      final bytes = base64Decode(pdfBase64);

      if (!kIsWeb &&
          (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
        final tmpDir = await getTemporaryDirectory();
        final path = '${tmpDir.path}/$fileName';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);

        if (!mounted) return;
        showDialog<void>(
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
                        await Share.shareXFiles([
                          XFile(
                            path,
                            mimeType: 'application/pdf',
                            name: fileName,
                          ),
                        ], subject: fileName);
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
                        await OpenFilex.open(path);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activityButtonYellow,
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

      // Web/desktop fallback: let user pick a location.
      final savePath = await getSaveLocation(
        acceptedTypeGroups: [pdfType],
        suggestedName: fileName,
      );
      if (savePath == null) return;
      final file = File(savePath.path);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${savePath.path}')));
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    }
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

  Future<void> _handleDocumentAction(String? link, String fallback) async {
    if (link == null || link.isEmpty) {
      _showSnack(fallback);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showSnack('Unable to open the document.');
      return;
    }
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      _showSnack('Unable to open the document.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setVerifiedStatus(
    DocumentReference<Map<String, dynamic>> ref, {
    required bool verified,
  }) async {
    try {
      await ref.set({
        'status': verified,
        if (verified) 'verifiedAt': FieldValue.serverTimestamp(),
        if (!verified) 'verifiedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      _showSnack(verified ? 'Marked as verified.' : 'Marked as unverified.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to update status. Please try again.');
    }
  }

  Future<void> _openEditSheet(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdminDocumentEditSheet(document: doc),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _deleteDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: activityBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this document?',
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: const Text(
          'This action cannot be undone.',
          textAlign: TextAlign.center,
          style: _dialogContentStyle,
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

    final data = document.data() ?? const <String, dynamic>{};
    final storagePath = (data['storagePath'] as String?)?.trim();
    if (storagePath != null && storagePath.isNotEmpty) {
      await FirebaseStorage.instance
          .ref(storagePath)
          .delete()
          .catchError((_) {});
    }

    await document.reference.delete();

    final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
    if (caregiverId.isNotEmpty) {
      await _removeFromCaregiverDocuments(caregiverId, document.id);
    }

    _showSnack('Document removed.');
  }

  Future<void> _removeFromCaregiverDocuments(
    String caregiverId,
    String docId,
  ) async {
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId);
    final snapshot = await caregiverRef.get();
    final raw = snapshot.data()?['documents'];
    final entries = <Map<String, dynamic>>[];
    if (raw is Iterable) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          entries.add(Map<String, dynamic>.from(item));
        } else if (item is Map) {
          entries.add(Map<String, dynamic>.from(item.cast()));
        }
      }
    }
    final filtered = entries.where((entry) => entry['id'] != docId).toList();
    await caregiverRef.set({'documents': filtered}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('documents')
        .orderBy('updatedAt', descending: true)
        .limit(220)
        .snapshots();

    final monthLabel = _monthLabel(_selectedMonth);
    final monthRange = _monthRange(_selectedMonth);
    final monthStartTs = Timestamp.fromDate(monthRange.start);
    final monthEndTs = Timestamp.fromDate(monthRange.end);

    final monthDocsStream = FirebaseFirestore.instance
        .collection('documents')
        .where('updatedAt', isGreaterThanOrEqualTo: monthStartTs)
        .where('updatedAt', isLessThan: monthEndTs)
        .limit(500)
        .snapshots();

    final headerWithHero = SizedBox(
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
            child: _DocumentsAnalyticsCard(
              monthLabel: monthLabel,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onGenerateReport: _generateMonthlyDocumentsReport,
              monthDocsStream: monthDocsStream,
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
          children: [headerWithHero],
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
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: stream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return _buildEmptyState(
                                icon: Icons.description_outlined,
                                title: 'Unable to load documents',
                                subtitle: 'Please try again.',
                              );
                            }

                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final docs = snapshot.data!.docs;
                            final search = _searchText.trim().toLowerCase();
                            final filtered = docs.where((d) {
                              if (search.isEmpty) return true;
                              final data = d.data();
                              final name = ((data['name'] as String?) ?? '')
                                  .toLowerCase();
                              final fileName =
                                  ((data['fileName'] as String?) ?? '')
                                      .toLowerCase();
                              final caregiverId =
                                  ((data['caregiverId'] as String?) ?? '')
                                      .toLowerCase();
                              if (d.id.toLowerCase().contains(search)) {
                                return true;
                              }
                              if (name.contains(search)) return true;
                              if (fileName.contains(search)) return true;
                              return caregiverId.contains(search);
                            }).toList();

                            final statusFiltered = filtered
                                .where((d) {
                                  if (_statusFilter ==
                                      _DocumentsStatusFilter.all) {
                                    return true;
                                  }
                                  final isVerified = d.data()['status'] == true;
                                  if (_statusFilter ==
                                      _DocumentsStatusFilter.verified) {
                                    return isVerified;
                                  }
                                  return !isVerified;
                                })
                                .toList(growable: false);

                            return ListView(
                              controller: _panelScrollController,
                              padding: EdgeInsets.only(
                                bottom: (bottomInset + 24).clamp(24.0, 64.0),
                              ),
                              physics: const ClampingScrollPhysics(),
                              children: [
                                _DocumentsSearchField(
                                  controller: _searchController,
                                ),
                                const SizedBox(height: 10),
                                _DocumentsFilterBar(
                                  selected: _statusFilter,
                                  onSelected: _setStatusFilter,
                                ),
                                Transform.translate(
                                  offset: const Offset(0, -60),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: statusFiltered.isEmpty
                                        ? SizedBox(
                                            height: 320,
                                            child: _buildEmptyState(
                                              icon: Icons.search_off_outlined,
                                              title: 'No results',
                                              subtitle:
                                                  'Try a different keyword.',
                                            ),
                                          )
                                        : ListView.separated(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: statusFiltered.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (context, index) {
                                              final doc = statusFiltered[index];
                                              final data = doc.data();
                                              return _AdminDocumentCard(
                                                indexNumber: index + 1,
                                                document: doc,
                                                onView: () => _handleDocumentAction(
                                                  (data['fileUrl']
                                                          as String?) ??
                                                      '',
                                                  'No file uploaded for this document.',
                                                ),
                                                onEdit: () =>
                                                    _openEditSheet(doc),
                                                onDelete: () =>
                                                    _deleteDocument(doc),
                                                onChangeStatus: (next) =>
                                                    _setVerifiedStatus(
                                                      doc.reference,
                                                      verified: next,
                                                    ),
                                              );
                                            },
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
      appBar: buildProfileStyleAppBar(
        title: 'Documents',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: content,
    );
  }
}

enum _DocumentsStatusFilter { all, verified, unverified }

Widget _buildEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: _tealAccent),
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

class _DocumentsSearchField extends StatelessWidget {
  const _DocumentsSearchField({required this.controller});

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
        hintText: 'Search document',
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

class _DocumentsFilterBar extends StatelessWidget {
  const _DocumentsFilterBar({required this.selected, required this.onSelected});

  final _DocumentsStatusFilter selected;
  final ValueChanged<_DocumentsStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _DocumentsStatusFilter.verified
        ? 'Verified documents'
        : selected == _DocumentsStatusFilter.unverified
        ? 'Unverified documents'
        : 'All documents';

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
                    selected: selected == _DocumentsStatusFilter.all,
                    onTap: () => onSelected(_DocumentsStatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Verified',
                    selected: selected == _DocumentsStatusFilter.verified,
                    onTap: () => onSelected(_DocumentsStatusFilter.verified),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Unverified',
                    selected: selected == _DocumentsStatusFilter.unverified,
                    onTap: () => onSelected(_DocumentsStatusFilter.unverified),
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

class _AdminDocumentCard extends StatelessWidget {
  const _AdminDocumentCard({
    required this.indexNumber,
    required this.document,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onChangeStatus,
  });

  final int indexNumber;
  final DocumentSnapshot<Map<String, dynamic>> document;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final data = document.data() ?? {};
    final uploadedAt = (data['updatedAt'] as Timestamp?)?.toDate();
    final uploadedLabel =
        uploadedAt != null ? _docDateFormat.format(uploadedAt) : 'unknown';
    final docName = ((data['name'] as String?) ?? 'Document').trim();
    final fileLabel = ((data['fileName'] as String?) ?? 'PDF File').trim();
    final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
    final isVerified = data['status'] as bool? ?? false;

    final borderColor = Colors.grey.shade300;
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
          FutureBuilder<Map<String, dynamic>?>(
            future: _loadCaregiverProfile(caregiverId),
            builder: (context, snapshot) {
              final caregiverData = snapshot.data;
              final caregiverName = _pickName(caregiverData);
              final caregiverPhoto = _pickPhotoUrl(caregiverData);

              final displayName =
                  caregiverName.isNotEmpty ? caregiverName : 'Unavailable';
              final documentName = docName.isNotEmpty ? docName : 'Document';

              return Column(
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
                            photoUrl: caregiverPhoto?.isNotEmpty == true
                                ? caregiverPhoto
                                : null,
                            label: displayName,
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
                                    displayName,
                                    style: _documentTitleStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PopupMenuButton<bool>(
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
                                  onSelected: onChangeStatus,
                                  itemBuilder: (context) => [
                                    PopupMenuItem<bool>(
                                      value: true,
                                      child: Row(
                                        children: [
                                          const Text(
                                            'Verified',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (isVerified)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 18,
                                            ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<bool>(
                                      value: false,
                                      child: Row(
                                        children: [
                                          const Text(
                                            'Unverified',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (!isVerified)
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 18,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  child: _StatusMenuChip(verified: isVerified),
                                ),
                              ],
                            ),
                            const SizedBox(height: UiTokens.s4),
                            Text(
                              documentName,
                              style: _documentFileStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: UiTokens.s10),
                  _InfoRow(label: 'Document ID', value: document.id),
                  _InfoRow(label: 'Name', value: caregiverName),
                  _InfoRow(label: 'Document', value: documentName),
                  _InfoRow(label: 'File', value: fileLabel),
                  _InfoRow(
                    label: 'Uploaded',
                    value: uploadedLabel,
                    showBorder: false,
                  ),
                ],
              );
            },
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
                child: _DocumentActionButton(
                  icon: Icons.remove_red_eye,
                  label: 'View',
                  onTap: onView,
                  primary: true,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _DocumentActionButton(
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
            crossAxisAlignment: CrossAxisAlignment.center,
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

class _DocumentActionButton extends StatelessWidget {
  const _DocumentActionButton({
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
    final backgroundColor = primary ? _tealAccent : Colors.white;
    final borderColor = primary ? _tealAccent : Colors.grey.shade300;
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

class _StatusMenuChip extends StatelessWidget {
  const _StatusMenuChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final label = verified ? 'Verified' : 'Unverified';
    final dotColor = verified ? Colors.green.shade700 : const Color(0xFFF4B63D);

    // Match the compact status chip used in admin bookings screen.
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

class _AdminDocumentEditSheet extends StatefulWidget {
  const _AdminDocumentEditSheet({required this.document});

  final DocumentSnapshot<Map<String, dynamic>> document;

  @override
  State<_AdminDocumentEditSheet> createState() =>
      _AdminDocumentEditSheetState();
}

class _AdminDocumentEditSheetState extends State<_AdminDocumentEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fileNameCtrl;
  final LayerLink _verifiedFieldLink = LayerLink();
  final GlobalKey _verifiedFieldKey = GlobalKey();
  OverlayEntry? _verifiedOverlayEntry;
  final TextEditingController _verifiedFieldController =
      TextEditingController();
  final TextEditingController _docIdController = TextEditingController();
  bool _verified = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.document.data() ?? const <String, dynamic>{};
    _nameCtrl = TextEditingController(text: (data['name'] as String?) ?? '');
    _fileNameCtrl = TextEditingController(
      text: (data['fileName'] as String?) ?? '',
    );
    _verified = data['status'] as bool? ?? false;
    _verifiedFieldController.text = _verified ? 'Verified' : 'Unverified';
    _docIdController.text = widget.document.id;
  }

  @override
  void dispose() {
    _closeVerifiedMenu();
    _nameCtrl.dispose();
    _fileNameCtrl.dispose();
    _verifiedFieldController.dispose();
    _docIdController.dispose();
    super.dispose();
  }

  void _toggleVerifiedMenu() {
    if (_verifiedOverlayEntry == null) {
      _openVerifiedMenu();
    } else {
      _closeVerifiedMenu();
    }
  }

  void _openVerifiedMenu() {
    _closeVerifiedMenu();
    final overlay = Overlay.of(context);

    final box =
        _verifiedFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    const options = [
      _VerifiedOption(label: 'Verified', value: true),
      _VerifiedOption(label: 'Unverified', value: false),
    ];

    _verifiedOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeVerifiedMenu,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _verifiedFieldLink,
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
                                  onTap: () => _selectVerified(option),
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
                                          decoration: BoxDecoration(
                                            color: option.value
                                                ? const Color(0xFF2BB673)
                                                : const Color(0xFFF4B63D),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            option.label,
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

    overlay.insert(_verifiedOverlayEntry!);
  }

  void _closeVerifiedMenu() {
    _verifiedOverlayEntry?.remove();
    _verifiedOverlayEntry = null;
  }

  void _selectVerified(_VerifiedOption option) {
    setState(() {
      _verified = option.value;
      _verifiedFieldController.text = option.label;
    });
    _closeVerifiedMenu();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.document.reference.set({
        'name': _nameCtrl.text.trim(),
        'fileName': _fileNameCtrl.text.trim(),
        'status': _verified,
        if (_verified) 'verifiedAt': FieldValue.serverTimestamp(),
        if (!_verified) 'verifiedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop();
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
    final data = widget.document.data() ?? const <String, dynamic>{};
    final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();

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
                          'Edit document',
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
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _loadCaregiverProfile(caregiverId),
                    builder: (context, snapshot) {
                      final caregiverData = snapshot.data;
                      final caregiverName = _pickName(caregiverData);
                      final caregiverPhoto = _pickPhotoUrl(caregiverData);
                      final displayName =
                          caregiverName.isNotEmpty ? caregiverName : 'Unavailable';

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
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _docIdController,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Document ID',
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
                        borderSide: BorderSide(
                          color: _profileDarkText,
                          width: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Document details',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CompositedTransformTarget(
                    link: _verifiedFieldLink,
                    child: TextFormField(
                      key: _verifiedFieldKey,
                      controller: _verifiedFieldController,
                      readOnly: true,
                      showCursor: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Verified',
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
                          borderSide: BorderSide(
                            color: _profileDarkText,
                            width: 1.1,
                          ),
                        ),
                        suffixIcon: const Icon(Icons.expand_more, size: 18),
                      ),
                      onTap: _toggleVerifiedMenu,
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
                    decoration: InputDecoration(
                      labelText: 'Document name',
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
                        borderSide: BorderSide(
                          color: _profileDarkText,
                          width: 1.1,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Please enter a document name.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _fileNameCtrl,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: InputDecoration(
                      labelText: 'File name',
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
                        borderSide: BorderSide(
                          color: _profileDarkText,
                          width: 1.1,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Please enter a file name.';
                      return null;
                    },
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifiedOption {
  const _VerifiedOption({required this.label, required this.value});

  final String label;
  final bool value;
}

class _DocumentsAnalyticsCard extends StatelessWidget {
  const _DocumentsAnalyticsCard({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.monthDocsStream,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Stream<QuerySnapshot<Map<String, dynamic>>> monthDocsStream;

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
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: monthDocsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final docs = snapshot.data?.docs ?? const [];
          var verified = 0;
          var pending = 0;
          for (final d in docs) {
            final data = d.data();
            if (data['status'] == true) {
              verified += 1;
            } else {
              pending += 1;
            }
          }
          final total = pending + verified;
          final segments = <_DonutSegment>[
            _DonutSegment(
              label: 'Pending',
              count: pending,
              color: const Color(0xFFF4B63D),
            ),
            _DonutSegment(
              label: 'Verified',
              count: verified,
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
                            label: 'Total activity',
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
                          if (s.label == 'Verified')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: onGenerateReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: activityButtonYellow,
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
