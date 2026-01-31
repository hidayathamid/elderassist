import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/ui_tokens.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

import '../user/activity/activity_screen.dart'
    show activityAccentBlue, activityBackgroundColor;

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _primaryBlue = Color(0xFF00A8A7);

const double _heroHeight = 220.0;
const double _headerCardOverlap = 96.0;
const double _panelMaxExtent = 0.96;

const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];
final DateFormat _adminDateFormat = DateFormat('MMM d, yyyy • h:mm a');

class AdminVerificationsScreen extends StatefulWidget {
  const AdminVerificationsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<AdminVerificationsScreen> createState() =>
      _AdminVerificationsScreenState();
}

class _AdminVerificationsScreenState extends State<AdminVerificationsScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;

  late DateTime _selectedMonth;
  _VerificationFilter _filter = _VerificationFilter.all;
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

  void _setFilter(_VerificationFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
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

  Future<void> _generateMonthlyVerificationsReport() async {
    final month = _selectedMonth;
    final range = _monthRange(month);
    final monthStart = Timestamp.fromDate(range.start);
    final monthEnd = Timestamp.fromDate(range.end);

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
      final withdrawSnap = await FirebaseFirestore.instance
          .collection('withdrawRequests')
          .where('requestedAt', isGreaterThanOrEqualTo: monthStart)
          .where('requestedAt', isLessThan: monthEnd)
          .get();
      final refundSnaps = await Future.wait([
        FirebaseFirestore.instance
            .collection('payments')
            .where('updatedAt', isGreaterThanOrEqualTo: monthStart)
            .where('updatedAt', isLessThan: monthEnd)
            .get(),
        FirebaseFirestore.instance
            .collection('payments')
            .where('createdAt', isGreaterThanOrEqualTo: monthStart)
            .where('createdAt', isLessThan: monthEnd)
            .get(),
      ]);
      final refundById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snap in refundSnaps) {
        for (final doc in snap.docs) {
          refundById[doc.id] = doc;
        }
      }
      final refundDocs = refundById.values
          .where((doc) {
            final status = ((doc.data()['paymentStatus'] as String?) ?? '')
                .trim();
            return status == 'REFUND_REQUESTED' || status == 'REFUNDED';
          })
          .toList(growable: false);

      final buffer = StringBuffer();
      buffer.writeln(
        'type,id,ownerId,secondaryId,status,amount,currency,createdAt',
      );

      String csvEscape(String input) {
        final safe = input.replaceAll('"', '""');
        if (safe.contains(',') || safe.contains('"') || safe.contains('\n')) {
          return '"$safe"';
        }
        return safe;
      }

      String formatTs(Timestamp? ts) {
        if (ts == null) return '';
        try {
          return _adminDateFormat.format(ts.toDate());
        } catch (_) {
          return '';
        }
      }

      for (final doc in withdrawSnap.docs) {
        final entry = _WithdrawRequestEntry.fromDoc(doc);
        final currency = (doc.data()['currency'] as String?)?.trim() ?? 'MYR';
        buffer.writeln(
          [
            'withdraw',
            csvEscape(entry.requestId),
            csvEscape(entry.caregiverId),
            csvEscape((doc.data()['weekKey'] as String?)?.trim() ?? ''),
            csvEscape(entry.status),
            entry.payoutAmount.toStringAsFixed(2),
            csvEscape(currency),
            csvEscape(formatTs(entry.requestedAt)),
          ].join(','),
        );
      }

      for (final doc in refundDocs) {
        final entry = _RefundPaymentEntry.fromDoc(doc);
        buffer.writeln(
          [
            'refund',
            csvEscape(entry.paymentId),
            csvEscape(entry.userId),
            csvEscape(entry.bookingId),
            csvEscape(entry.paymentStatus),
            entry.amount.toStringAsFixed(2),
            csvEscape(
              (doc.data()['currency'] as String?)?.trim() ??
                  (doc.data()['currencyCode'] as String?)?.trim() ??
                  'MYR',
            ),
            csvEscape(formatTs(entry.createdAt)),
          ].join(','),
        );
      }

      final fileName =
          'verifications-report-${month.year}-${month.month.toString().padLeft(2, '0')}.csv';
      final bytes = utf8.encode(buffer.toString());

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
                        await Share.shareXFiles([
                          XFile(path, mimeType: 'text/csv', name: fileName),
                        ], subject: fileName);
                      },
                      style: OutlinedButton.styleFrom(
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4B63D),
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
            ],
          ),
        );
        return;
      }

      final location = await getSaveLocation(suggestedName: fileName);
      if (location == null) return;
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      closeLoadingIfOpen();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to generate report. Please try again.'),
        ),
      );
    } finally {
      closeLoadingIfOpen();
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

  Future<void> _openAdminBottomSheet(Widget sheet) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => sheet,
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  void _handleViewEntry(_VerificationEntry entry) {
    switch (entry.kind) {
      case _VerificationKind.withdraw:
        _openAdminBottomSheet(
          _WithdrawRequestDetailsSheet(requestDoc: entry.doc),
        );
      case _VerificationKind.refund:
        _openAdminBottomSheet(_RefundRequestDetailsSheet(paymentDoc: entry.doc));
    }
  }

  void _handleEditEntry(_VerificationEntry entry) {
    switch (entry.kind) {
      case _VerificationKind.withdraw:
        _openAdminBottomSheet(_WithdrawRequestEditSheet(requestDoc: entry.doc));
      case _VerificationKind.refund:
        _openAdminBottomSheet(_RefundRequestEditSheet(paymentDoc: entry.doc));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('withdrawRequests')
        .orderBy('requestedAt', descending: true)
        .limit(220)
        .snapshots();

    final refundStream = FirebaseFirestore.instance
        .collection('payments')
        .where('paymentStatus', whereIn: const ['REFUND_REQUESTED', 'REFUNDED'])
        .limit(220)
        .snapshots();

    final monthLabel = _monthLabel(_selectedMonth);
    final monthRange = _monthRange(_selectedMonth);
    final monthStartTs = Timestamp.fromDate(monthRange.start);
    final monthEndTs = Timestamp.fromDate(monthRange.end);

    final monthWithdrawStream = FirebaseFirestore.instance
        .collection('withdrawRequests')
        .orderBy('requestedAt', descending: true)
        .limit(500)
        .snapshots();

    final monthRefundStream = FirebaseFirestore.instance
        .collection('payments')
        .orderBy('updatedAt', descending: true)
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
            child: _VerificationsAnalyticsCard(
              monthLabel: monthLabel,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onGenerateReport: _generateMonthlyVerificationsReport,
              monthStart: monthStartTs,
              monthEnd: monthEndTs,
              withdrawStream: monthWithdrawStream,
              refundStream: monthRefundStream,
            ),
          ),
        ],
      ),
    );

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final scrimTopInset = MediaQuery.of(context).padding.top + kToolbarHeight;
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
                          builder: (context, withdrawSnapshot) {
                            if (withdrawSnapshot.hasError) {
                              return _buildEmptyState(
                                icon: Icons.payments_outlined,
                                title: 'Unable to load verifications',
                                subtitle: 'Please try again.',
                              );
                            }
                            if (!withdrawSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>
                            >(
                              stream: refundStream,
                              builder: (context, refundSnapshot) {
                                if (refundSnapshot.hasError) {
                                  return _buildEmptyState(
                                    icon: Icons.payments_outlined,
                                    title: 'Unable to load verifications',
                                    subtitle: 'Please try again.',
                                  );
                                }
                                if (!refundSnapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final withdrawDocs =
                                    withdrawSnapshot.data!.docs;
                                final refundDocs = refundSnapshot.data!.docs;

                                final entries = <_VerificationEntry>[];
                                if (_filter == _VerificationFilter.all ||
                                    _filter == _VerificationFilter.withdraw) {
                                  for (final doc in withdrawDocs) {
                                    final entry = _WithdrawRequestEntry.fromDoc(
                                      doc,
                                    );
                                    entries.add(
                                      _VerificationEntry.withdraw(
                                        doc: doc,
                                        entry: entry,
                                      ),
                                    );
                                  }
                                }
                                if (_filter == _VerificationFilter.all ||
                                    _filter == _VerificationFilter.refund) {
                                  for (final doc in refundDocs) {
                                    final entry = _RefundPaymentEntry.fromDoc(
                                      doc,
                                    );
                                    if (entry.userId.trim().isEmpty) continue;
                                    entries.add(
                                      _VerificationEntry.refund(
                                        doc: doc,
                                        entry: entry,
                                      ),
                                    );
                                  }
                                }

                                entries.sort(
                                  (a, b) =>
                                      (b.sortEpoch).compareTo(a.sortEpoch),
                                );

                                final search = _searchText.trim().toLowerCase();
                                final searched = entries
                                    .where((e) {
                                      if (search.isEmpty) return true;
                                      if (e.id.toLowerCase().contains(search)) {
                                        return true;
                                      }
                                      if (e.ownerId.toLowerCase().contains(
                                        search,
                                      )) {
                                        return true;
                                      }
                                      if (e.secondaryId.toLowerCase().contains(
                                        search,
                                      )) {
                                        return true;
                                      }
                                      return e.status.toLowerCase().contains(
                                        search,
                                      );
                                    })
                                    .toList(growable: false);

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
                                    _VerificationsSearchField(
                                      controller: _searchController,
                                    ),
                                    const SizedBox(height: 10),
                                    _VerificationsFilterBar(
                                      selected: _filter,
                                      onSelected: _setFilter,
                                    ),
                                    Transform.translate(
                                      offset: const Offset(0, -60),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: searched.isEmpty
                                            ? SizedBox(
                                                height: 320,
                                                child: _buildEmptyState(
                                                  icon:
                                                      Icons.search_off_outlined,
                                                  title: 'No results',
                                                  subtitle:
                                                      'Try a different keyword.',
                                                ),
                                              )
                                            : ListView.separated(
                                                shrinkWrap: true,
                                                physics:
                                                    const NeverScrollableScrollPhysics(),
                                                itemCount: searched.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(height: 10),
                                                itemBuilder: (context, index) {
                                                  final entry = searched[index];
                                                   return _AdminVerificationCard(
                                                     indexNumber: index + 1,
                                                     entry: entry,
                                                     onView: () =>
                                                         _handleViewEntry(entry),
                                                     onEdit: () =>
                                                         _handleEditEntry(entry),
                                                   );
                                                 },
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
      appBar: buildProfileStyleAppBar(
        title: 'Verifications',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: content,
    );
  }
}

enum _VerificationFilter { all, withdraw, refund }

enum _VerificationKind { withdraw, refund }

class _VerificationEntry {
  const _VerificationEntry._({
    required this.kind,
    required this.id,
    required this.ownerId,
    required this.secondaryId,
    required this.status,
    required this.amount,
    required this.when,
    required this.doc,
    required this.verified,
  });

  factory _VerificationEntry.withdraw({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required _WithdrawRequestEntry entry,
  }) {
    return _VerificationEntry._(
      kind: _VerificationKind.withdraw,
      id: entry.requestId,
      ownerId: entry.caregiverId,
      secondaryId: '',
      status: entry.status,
      amount: entry.payoutAmount,
      when: entry.requestedAt,
      doc: doc,
      verified: doc.data()['verified'] as bool?,
    );
  }

  factory _VerificationEntry.refund({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required _RefundPaymentEntry entry,
  }) {
    final verified = doc.data()['verified'] as bool?;
    return _VerificationEntry._(
      kind: _VerificationKind.refund,
      id: entry.paymentId,
      ownerId: entry.userId,
      secondaryId: entry.bookingId,
      status: (verified ?? false) ? 'Verified' : 'Unverified',
      amount: entry.amount,
      when: entry.createdAt,
      doc: doc,
      verified: verified,
    );
  }

  final _VerificationKind kind;
  final String id;
  final String ownerId;
  final String secondaryId;
  final String status;
  final double amount;
  final Timestamp? when;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool? verified;

  int get sortEpoch => when?.millisecondsSinceEpoch ?? 0;
}

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
                color: Colors.black,
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

class _VerificationsSearchField extends StatelessWidget {
  const _VerificationsSearchField({required this.controller});

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
        hintText: 'Search request',
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
          horizontal: 14,
          vertical: 10,
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

class _VerificationsFilterBar extends StatelessWidget {
  const _VerificationsFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final _VerificationFilter selected;
  final ValueChanged<_VerificationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _VerificationFilter.withdraw
        ? 'Withdraw requests'
        : selected == _VerificationFilter.refund
        ? 'Refund requests'
        : 'All requests';

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
                    selected: selected == _VerificationFilter.all,
                    onTap: () => onSelected(_VerificationFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Withdraw',
                    selected: selected == _VerificationFilter.withdraw,
                    onTap: () => onSelected(_VerificationFilter.withdraw),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Refund',
                    selected: selected == _VerificationFilter.refund,
                    onTap: () => onSelected(_VerificationFilter.refund),
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

class _VerificationsAnalyticsCard extends StatelessWidget {
  const _VerificationsAnalyticsCard({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.monthStart,
    required this.monthEnd,
    required this.withdrawStream,
    required this.refundStream,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Timestamp monthStart;
  final Timestamp monthEnd;
  final Stream<QuerySnapshot<Map<String, dynamic>>> withdrawStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> refundStream;

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
        stream: withdrawStream,
        builder: (context, withdrawSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: refundStream,
            builder: (context, refundSnap) {
              final monthStartMs = monthStart.millisecondsSinceEpoch;
              final monthEndMs = monthEnd.millisecondsSinceEpoch;

              bool inMonth(Timestamp? ts) {
                if (ts == null) return false;
                final ms = ts.millisecondsSinceEpoch;
                return ms >= monthStartMs && ms < monthEndMs;
              }

              final withdrawDocs =
                  withdrawSnap.hasError ? const [] : (withdrawSnap.data?.docs ?? const []);
              final refundDocs =
                  refundSnap.hasError ? const [] : (refundSnap.data?.docs ?? const []);

              var withdrawCount = 0;
              var refundCount = 0;

              var pendingCount = 0;
              for (final d in withdrawDocs) {
                final data = d.data();
                final ts = data['requestedAt'] as Timestamp?;
                if (!inMonth(ts)) continue;
                withdrawCount += 1;
                final status = ((data['status'] as String?) ?? '').trim();
                if (status.toLowerCase() == 'pending') {
                  pendingCount += 1;
                }
              }
              for (final d in refundDocs) {
                final data = d.data();
                final status = ((data['paymentStatus'] as String?) ?? '').trim();
                if (status != 'REFUND_REQUESTED' && status != 'REFUNDED') {
                  continue;
                }
                final ts =
                    (data['updatedAt'] as Timestamp?) ??
                    (data['createdAt'] as Timestamp?) ??
                    (data['paidAt'] as Timestamp?);
                if (!inMonth(ts)) continue;
                refundCount += 1;
                if (status == 'REFUND_REQUESTED') {
                  pendingCount += 1;
                }
              }

              final total = withdrawCount + refundCount;
              final segments = <_DonutSegment>[
                _DonutSegment(
                  label: 'Withdraw',
                  count: withdrawCount,
                  color: const Color(0xFFF4B63D),
                ),
                _DonutSegment(
                  label: 'Refund',
                  count: refundCount,
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LegendRow(
                                color: Colors.black.withValues(alpha: 0.22),
                                label: 'Pending',
                                value: pendingCount,
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
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: onGenerateReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF4B63D),
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

class _AdminVerificationCard extends StatelessWidget {
  const _AdminVerificationCard({
    required this.indexNumber,
    required this.entry,
    required this.onView,
    required this.onEdit,
  });

  final int indexNumber;
  final _VerificationEntry entry;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ownerRef = entry.ownerId.trim().isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection(
                entry.kind == _VerificationKind.withdraw
                    ? 'caregivers'
                    : 'users',
              )
              .doc(entry.ownerId);

    final borderColor = Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: _cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: ownerRef?.get(),
        builder: (context, snapshot) {
          final ownerData = snapshot.data?.data();
          final ownerName =
              (ownerData?['name'] as String?)?.trim() ?? entry.ownerId;
          final ownerPhoto =
              (ownerData?['profile_photo'] as String?)?.trim() ??
              (ownerData?['photoUrl'] as String?)?.trim();

          final kindLabel = entry.kind == _VerificationKind.withdraw
              ? 'Withdraw'
              : 'Refund';
          final idLabel = entry.kind == _VerificationKind.withdraw
              ? 'Request ID'
              : 'Payment ID';
          final createdLabel = entry.kind == _VerificationKind.withdraw
              ? 'Requested'
              : 'Created';
          final dateLabel = entry.when == null
              ? '$createdLabel: unknown'
              : '$createdLabel: ${_adminDateFormat.format(entry.when!.toDate())}';

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
                        photoUrl: ownerPhoto?.isNotEmpty == true
                            ? ownerPhoto
                            : null,
                        label: ownerName.isNotEmpty ? ownerName : '?',
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
                                ownerName.isNotEmpty ? ownerName : 'User',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _profileDarkText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _VerificationStatusChip(
                              label: entry.status.trim().isEmpty
                                  ? 'Pending'
                                  : entry.status.trim(),
                              dotColor: entry.kind == _VerificationKind.refund
                                  ? ((entry.verified ?? false)
                                      ? Colors.green.shade700
                                      : const Color(0xFFF4B63D))
                                  : const Color(0xFFF4B63D),
                            ),
                          ],
                        ),
                        const SizedBox(height: UiTokens.s4),
                        Text(
                          '$kindLabel • RM ${entry.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _profileDarkText60,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: UiTokens.s10),
              _InfoRow(label: idLabel, value: entry.id),
              _InfoRow(label: 'Owner ID', value: entry.ownerId),
              if (entry.secondaryId.trim().isNotEmpty)
                _InfoRow(label: 'Booking ID', value: entry.secondaryId),
              _InfoRow(label: 'Date', value: dateLabel, showBorder: false),
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
                    child: _VerificationActionButton(
                      icon: Icons.remove_red_eye,
                      label: 'View',
                      onTap: onView,
                      primary: true,
                    ),
                  ),
                  const SizedBox(width: UiTokens.s8),
                  Expanded(
                    child: _VerificationActionButton(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: onEdit,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationActionButton extends StatelessWidget {
  const _VerificationActionButton({
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

class _VerificationStatusChip extends StatelessWidget {
  const _VerificationStatusChip({required this.label, required this.dotColor});

  final String label;
  final Color dotColor;

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

class _RefundRequestDetailsSheet extends StatelessWidget {
  const _RefundRequestDetailsSheet({required this.paymentDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> paymentDoc;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                          'Refund request',
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
                  _RefundRequestDetailsTabs(paymentDoc: paymentDoc),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WithdrawRequestDetailsSheet extends StatelessWidget {
  const _WithdrawRequestDetailsSheet({required this.requestDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> requestDoc;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                          'Withdraw request',
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
                  _WithdrawRequestDetailsTabs(requestDoc: requestDoc),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WithdrawRequestDetailsTabs extends StatefulWidget {
  const _WithdrawRequestDetailsTabs({required this.requestDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> requestDoc;

  @override
  State<_WithdrawRequestDetailsTabs> createState() =>
      _WithdrawRequestDetailsTabsState();
}

class _WithdrawRequestDetailsTabsState extends State<_WithdrawRequestDetailsTabs> {
  int _selectedTabIndex = 0;

  static const Color _cardBorder = Color(0xFFEBEDF0);
  static const Color _accentGreen = Color(0xFF00A8A7);
  static const Color _cardShadow = Color(0x1A0B0C10);
  static const Color _cardBorderStrong = Color(0xFFE1E4EA);
  static const double _cardRadius = 18;
  static const Color _mutedText = Color(0xFF6B7280);
  static const Color _avatarOutlineColor = Colors.white;

  BoxDecoration _premiumCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_cardRadius),
      border: Border.all(color: _cardBorderStrong),
      boxShadow: const [
        BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
      ],
    );
  }

  Widget _sectionHeader(String title, {String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: _profileDarkText,
              letterSpacing: -0.15,
            ),
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

  Widget _centerAvatar(String label, String? photoUrl) {
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
          radius: 34,
          photoUrl: (photoUrl?.trim().isNotEmpty == true) ? photoUrl!.trim() : null,
          label: label,
        ),
      ),
    );
  }

  Widget _infoRow({
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _mutedText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _profileDarkText,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadCaregiver(String caregiverId) async {
    if (caregiverId.trim().isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId)
        .get();
    return snap.data();
  }

  @override
  Widget build(BuildContext context) {
    const tabLabels = <String>[
      'Caregiver details',
      'Payout account',
      'Request details',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivityStyleTabs(
          labels: tabLabels,
          selectedIndex: _selectedTabIndex,
          onSelected: (index) => setState(() => _selectedTabIndex = index),
        ),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestDoc.reference.snapshots(),
          builder: (context, requestSnap) {
            final request = requestSnap.data?.data() ?? widget.requestDoc.data();
            final caregiverId = ((request['caregiverId'] as String?) ?? '').trim();
            final status = ((request['status'] as String?) ?? '').trim();
            final amount = _readMoney(request['payoutAmount']);
            final requestedAt = request['requestedAt'] as Timestamp?;
            final breakdown = _withdrawNetBreakdown(amount);

            return FutureBuilder<Map<String, dynamic>?>(
              future: _loadCaregiver(caregiverId),
              builder: (context, caregiverSnap) {
                final caregiver = caregiverSnap.data;
                final name = ((caregiver?['name'] as String?) ?? '').trim();
                final email = ((caregiver?['email'] as String?) ?? '').trim();
                final phone = ((caregiver?['phone'] as String?) ?? '').trim();
                final photoUrl =
                    ((caregiver?['profile_photo'] as String?) ?? '').trim().isNotEmpty
                        ? ((caregiver?['profile_photo'] as String?) ?? '').trim()
                        : ((caregiver?['photoUrl'] as String?) ?? '').trim();
                final address =
                    ((caregiver?['defaultAddress'] as String?) ?? '').trim().isNotEmpty
                        ? ((caregiver?['defaultAddress'] as String?) ?? '').trim()
                        : ((caregiver?['address'] as String?) ?? '').trim();

                Widget content;
                if (_selectedTabIndex == 0) {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader('Caregiver details'),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                              child: Column(
                                children: [
                                  _centerAvatar(
                                    name.isNotEmpty ? name : caregiverId,
                                    photoUrl,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    name.isNotEmpty ? name : 'Caregiver',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: _profileDarkText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    caregiverId.isNotEmpty ? caregiverId : '-',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black.withValues(alpha: 0.55),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: _cardBorder),
                            _infoRow(
                              icon: Icons.email_outlined,
                              title: 'Email',
                              value: email.isNotEmpty ? email : '-',
                            ),
                            _infoRow(
                              icon: Icons.phone_android,
                              title: 'Contact',
                              value: phone.isNotEmpty ? phone : '-',
                            ),
                            _infoRow(
                              icon: Icons.home_outlined,
                              title: 'Location',
                              value: address.isNotEmpty ? address : '-',
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else if (_selectedTabIndex == 1) {
                  final details = (caregiver?['paymentDetails'] as Map?)
                      ?.cast<String, dynamic>();
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(
                        'Payout account details',
                        hint: 'Pulled from Payments & Billing.',
                      ),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            _infoRow(
                              icon: Icons.account_balance_outlined,
                              title: 'Bank',
                              value: ((details?['bankName'] as String?) ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? ((details?['bankName'] as String?) ?? '')
                                      .trim()
                                  : '-',
                            ),
                            _infoRow(
                              icon: Icons.person_outline,
                              title: 'Account name',
                              value: ((details?['accountName'] as String?) ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? ((details?['accountName'] as String?) ?? '')
                                      .trim()
                                  : '-',
                            ),
                            _infoRow(
                              icon: Icons.confirmation_number_outlined,
                              title: 'Account number',
                              value:
                                  ((details?['accountNumber'] as String?) ?? '')
                                          .trim()
                                          .isNotEmpty
                                      ? ((details?['accountNumber'] as String?) ??
                                              '')
                                          .trim()
                                      : '-',
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(
                        'Request details',
                        hint: 'Requested amount shown after payment charges.',
                      ),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            _infoRow(
                              icon: Icons.receipt_long_outlined,
                              title: 'Request ID',
                              value: widget.requestDoc.id,
                            ),
                            _infoRow(
                              icon: Icons.person_outline,
                              title: 'Caregiver ID',
                              value: caregiverId.isNotEmpty ? caregiverId : '-',
                            ),
                            _infoRow(
                              icon: Icons.flag_outlined,
                              title: 'Status',
                              value: status.isNotEmpty ? status : '-',
                            ),
                            _infoRow(
                              icon: Icons.payments_outlined,
                              title: 'Original amount',
                              value: _formatRm(amount),
                            ),
                            _infoRow(
                              icon: Icons.calculate_outlined,
                              title: 'Payout amount',
                              value: _formatRm(breakdown.netAmount),
                            ),
                            _infoRow(
                              icon: Icons.schedule,
                              title: 'Requested at',
                              value: requestedAt == null
                                  ? '-'
                                  : _adminDateFormat.format(requestedAt.toDate()),
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return content;
              },
            );
          },
        ),
      ],
    );
  }
}

class _RefundRequestDetailsTabs extends StatefulWidget {
  const _RefundRequestDetailsTabs({required this.paymentDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> paymentDoc;

  @override
  State<_RefundRequestDetailsTabs> createState() =>
      _RefundRequestDetailsTabsState();
}

class _RefundRequestDetailsTabsState extends State<_RefundRequestDetailsTabs> {
  int _selectedTabIndex = 0;

  static const Color _cardBorder = Color(0xFFEBEDF0);
  static const Color _accentGreen = Color(0xFF00A8A7);
  static const Color _cardShadow = Color(0x1A0B0C10);
  static const Color _cardBorderStrong = Color(0xFFE1E4EA);
  static const double _cardRadius = 18;
  static const Color _mutedText = Color(0xFF6B7280);
  static const Color _avatarOutlineColor = Colors.white;

  BoxDecoration _premiumCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_cardRadius),
      border: Border.all(color: _cardBorderStrong),
      boxShadow: const [
        BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
      ],
    );
  }

  Widget _sectionHeader(String title, {String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: _profileDarkText,
              letterSpacing: -0.15,
            ),
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

  Widget _centerAvatar(String label, String? photoUrl) {
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
          radius: 34,
          photoUrl: (photoUrl?.trim().isNotEmpty == true)
              ? photoUrl!.trim()
              : null,
          label: label,
        ),
      ),
    );
  }

  Widget _infoRow({
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _mutedText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _profileDarkText,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadUser(String userId) async {
    if (userId.trim().isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return snap.data();
  }

  @override
  Widget build(BuildContext context) {
    const tabLabels = <String>[
      'User details',
      'Payout account',
      'Request details',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivityStyleTabs(
          labels: tabLabels,
          selectedIndex: _selectedTabIndex,
          onSelected: (index) => setState(() => _selectedTabIndex = index),
        ),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.paymentDoc.reference.snapshots(),
          builder: (context, paymentSnap) {
            final payment =
                paymentSnap.data?.data() ?? widget.paymentDoc.data();
            final userId = ((payment['userId'] as String?) ?? '').trim();
            final bookingId = ((payment['bookingId'] as String?) ?? '').trim();
            final status = ((payment['paymentStatus'] as String?) ?? '').trim();
            final amount = _readMoney(payment['amount']);
            final amountLabel = amount.toStringAsFixed(2);
            final netAmount = _refundNetAmount(amount);
            final netAmountLabel = netAmount.toStringAsFixed(2);
            final createdAt =
                (payment['updatedAt'] as Timestamp?) ??
                (payment['createdAt'] as Timestamp?) ??
                (payment['paidAt'] as Timestamp?);

            return FutureBuilder<Map<String, dynamic>?>(
              future: _loadUser(userId),
              builder: (context, userSnap) {
                final user = userSnap.data;

                Widget content;
                if (_selectedTabIndex == 0) {
                  final name = ((user?['name'] as String?) ?? '').trim();
                  final email = ((user?['email'] as String?) ?? '').trim();
                  final phone = ((user?['phone'] as String?) ?? '').trim();
                  final role = ((user?['role'] as String?) ?? 'user').trim();
                  final photoUrl = ((user?['photoUrl'] as String?) ?? '')
                      .trim();
                  final address = ((user?['defaultAddress'] as String?) ?? '')
                      .trim();

                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(
                        'User details',
                        hint: 'Role shown for reference.',
                      ),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                              child: Column(
                                children: [
                                  _centerAvatar(
                                    name.isNotEmpty ? name : userId,
                                    photoUrl,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    name.isNotEmpty ? name : 'User',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: _profileDarkText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (userId.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      userId,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _infoRow(
                              icon: Icons.badge_outlined,
                              title: 'Role',
                              value: role.isNotEmpty ? role : '—',
                            ),
                            _infoRow(
                              icon: Icons.email_outlined,
                              title: 'Email',
                              value: email.isNotEmpty ? email : '—',
                            ),
                            _infoRow(
                              icon: Icons.phone_android,
                              title: 'Contact',
                              value: phone.isNotEmpty ? phone : '—',
                            ),
                            _infoRow(
                              icon: Icons.home_outlined,
                              title: 'Location',
                              value: address.isNotEmpty ? address : '—',
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else if (_selectedTabIndex == 1) {
                  final details = (user?['paymentDetails'] as Map?)
                      ?.cast<String, dynamic>();
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(
                        'Payout account details',
                        hint: 'Pulled from Payments & Billing.',
                      ),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            _infoRow(
                              icon: Icons.account_balance_outlined,
                              title: 'Bank',
                              value:
                                  ((details?['bankName'] as String?) ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? ((details?['bankName'] as String?) ?? '')
                                        .trim()
                                  : '—',
                            ),
                            _infoRow(
                              icon: Icons.person_outline,
                              title: 'Account name',
                              value:
                                  ((details?['accountName'] as String?) ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? ((details?['accountName'] as String?) ?? '')
                                        .trim()
                                  : '—',
                            ),
                            _infoRow(
                              icon: Icons.confirmation_number_outlined,
                              title: 'Account number',
                              value:
                                  ((details?['accountNumber'] as String?) ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? ((details?['accountNumber'] as String?) ??
                                            '')
                                        .trim()
                                  : '—',
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader('Request details'),
                      Container(
                        decoration: _premiumCardDecoration(),
                        child: Column(
                          children: [
                            _infoRow(
                              icon: Icons.receipt_long_outlined,
                              title: 'Payment ID',
                              value: widget.paymentDoc.id,
                            ),
                            _infoRow(
                              icon: Icons.bookmark_outline,
                              title: 'Booking ID',
                              value: bookingId.isNotEmpty ? bookingId : '—',
                            ),
                            _infoRow(
                              icon: Icons.person_outline,
                              title: 'User ID',
                              value: userId.isNotEmpty ? userId : '—',
                            ),
                            _infoRow(
                              icon: Icons.flag_outlined,
                              title: 'Status',
                              value: status.isNotEmpty ? status : '—',
                            ),
                            _infoRow(
                              icon: Icons.payments_outlined,
                              title: 'Original amount',
                              value: 'RM $amountLabel',
                            ),
                            _infoRow(
                              icon: Icons.calculate_outlined,
                              title: 'Request amount',
                              value: 'RM $netAmountLabel',
                            ),
                            _infoRow(
                              icon: Icons.schedule,
                              title: 'Created at',
                              value: createdAt == null
                                  ? '—'
                                  : _adminDateFormat.format(createdAt.toDate()),
                              showBorder: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return content;
              },
            );
          },
        ),
      ],
    );
  }
}

class _ActivityStyleTabs extends StatelessWidget {
  const _ActivityStyleTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                  color: selected ? const Color(0xFFF4B63D) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFF4B63D)
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
    );
  }
}

class _WithdrawRequestEditSheet extends StatefulWidget {
  const _WithdrawRequestEditSheet({required this.requestDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> requestDoc;

  @override
  State<_WithdrawRequestEditSheet> createState() =>
      _WithdrawRequestEditSheetState();
}

class _VerifiedOption {
  const _VerifiedOption({required this.label, required this.value});

  final String label;
  final bool value;
}

class _WithdrawRequestEditSheetState extends State<_WithdrawRequestEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final LayerLink _verifiedFieldLink = LayerLink();
  final GlobalKey _verifiedFieldKey = GlobalKey();
  OverlayEntry? _verifiedOverlayEntry;

  late final TextEditingController _requestIdCtrl;
  late final TextEditingController _verifiedCtrl;
  late final TextEditingController _receiptFileCtrl;

  bool _verifiedValue = false;
  bool _saving = false;

  Uint8List? _selectedReceiptBytes;
  String? _existingReceiptUrl;
  String? _existingReceiptStoragePath;

  static const _verifiedOptions = <_VerifiedOption>[
    _VerifiedOption(label: 'Verified', value: true),
    _VerifiedOption(label: 'Unverified', value: false),
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.requestDoc.data();
    _requestIdCtrl = TextEditingController(text: widget.requestDoc.id);
    _verifiedValue = data['verified'] == true;
    _verifiedCtrl = TextEditingController(
      text: _verifiedValue ? 'Verified' : 'Unverified',
    );
    _receiptFileCtrl = TextEditingController(
      text: ((data['receiptFileName'] as String?) ?? '').trim(),
    );
    _existingReceiptUrl = (data['receiptUrl'] as String?)?.trim();
    _existingReceiptStoragePath = (data['receiptStoragePath'] as String?)
        ?.trim();
  }

  @override
  void dispose() {
    _closeVerifiedMenu();
    _requestIdCtrl.dispose();
    _verifiedCtrl.dispose();
    _receiptFileCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
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
                          children: _verifiedOptions
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
                                                ? Colors.green.shade700
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
                                        if (_verifiedValue == option.value)
                                          const Icon(
                                            Icons.check_rounded,
                                            size: 18,
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
      _verifiedValue = option.value;
      _verifiedCtrl.text = option.label;
    });
    _closeVerifiedMenu();
  }

  Future<void> _pickReceiptFile() async {
    final pdfGroup = const XTypeGroup(label: 'pdf', extensions: ['pdf']);
    final picked = await openFile(
      acceptedTypeGroups: [pdfGroup],
      confirmButtonText: 'Select',
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() {
      _selectedReceiptBytes = bytes;
      _receiptFileCtrl.text = picked.name;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      final data = widget.requestDoc.data();
      final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
      String? receiptUrl = _existingReceiptUrl;
      String? receiptStoragePath = _existingReceiptStoragePath;

      if (_selectedReceiptBytes != null) {
        final uploadPath =
            'withdrawReceipts/$caregiverId/${widget.requestDoc.id}.pdf';
        final ref = FirebaseStorage.instance.ref(uploadPath);
        await ref.putData(
          _selectedReceiptBytes!,
          SettableMetadata(contentType: 'application/pdf'),
        );
        receiptUrl = await ref.getDownloadURL();
        if (receiptStoragePath != null &&
            receiptStoragePath.isNotEmpty &&
            receiptStoragePath != uploadPath) {
          await FirebaseStorage.instance
              .ref(receiptStoragePath)
              .delete()
              .catchError((_) {});
        }
        receiptStoragePath = uploadPath;
      }

      final receiptFileName = _receiptFileCtrl.text.trim();
      await widget.requestDoc.reference.set({
        'verified': _verifiedValue,
        if (_verifiedValue) 'verifiedAt': FieldValue.serverTimestamp(),
        if (!_verifiedValue) 'verifiedAt': FieldValue.delete(),
        if (receiptFileName.isNotEmpty) 'receiptFileName': receiptFileName,
        if (receiptFileName.isEmpty) 'receiptFileName': FieldValue.delete(),
        if (receiptUrl != null && receiptUrl.trim().isNotEmpty)
          'receiptUrl': receiptUrl.trim(),
        if (receiptUrl == null || receiptUrl.trim().isEmpty)
          'receiptUrl': FieldValue.delete(),
        if (receiptStoragePath != null && receiptStoragePath.trim().isNotEmpty)
          'receiptStoragePath': receiptStoragePath.trim(),
        if (receiptStoragePath == null || receiptStoragePath.trim().isEmpty)
          'receiptStoragePath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final data = widget.requestDoc.data();
    final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);
    final amount = _readMoney(data['payoutAmount']);
    final netAmount = _withdrawNetBreakdown(amount).netAmount;

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
                          'Withdraw request',
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
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: caregiverRef?.get(),
                    builder: (context, snapshot) {
                      final caregiverData = snapshot.data?.data();
                      final caregiverName =
                          (caregiverData?['name'] as String?)?.trim() ??
                          caregiverId;
                      final caregiverPhoto =
                          (caregiverData?['profile_photo'] as String?)
                              ?.trim() ??
                          (caregiverData?['photoUrl'] as String?)?.trim();
                      return Column(
                        children: [
                          DefaultProfileAvatar(
                            radius: 34,
                            photoUrl: caregiverPhoto?.isNotEmpty == true
                                ? caregiverPhoto
                                : null,
                            label: caregiverName.isNotEmpty
                                ? caregiverName
                                : '?',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            caregiverName.isNotEmpty
                                ? caregiverName
                                : 'Caregiver',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: _profileDarkText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (caregiverId.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              caregiverId,
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
                    controller: _requestIdCtrl,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration('Request ID'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Withdraw details',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: netAmount > 0
                        ? 'RM ${netAmount.toStringAsFixed(2)}'
                        : '-',
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration('Requested amount'),
                  ),
                  const SizedBox(height: 10),
                  CompositedTransformTarget(
                    link: _verifiedFieldLink,
                    child: TextFormField(
                      key: _verifiedFieldKey,
                      controller: _verifiedCtrl,
                      readOnly: true,
                      showCursor: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: _fieldDecoration(
                        'Verified',
                        suffixIcon: const Icon(Icons.expand_more, size: 18),
                      ),
                      onTap: _saving ? null : _toggleVerifiedMenu,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _receiptFileCtrl,
                    readOnly: true,
                    showCursor: false,
                    onTap: _saving ? null : _pickReceiptFile,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration(
                      'Receipt file',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.upload_file, size: 18),
                        onPressed: _saving ? null : _pickReceiptFile,
                      ),
                    ),
                    validator: (_) {
                      if (!_verifiedValue) return null;
                      final hasExisting = (_existingReceiptUrl ?? '')
                          .trim()
                          .isNotEmpty;
                      final hasSelected = _selectedReceiptBytes != null;
                      if (!hasExisting && !hasSelected) {
                        return 'Upload receipt to mark as verified.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF only. Receipt will be stored on this request.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4B63D),
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

class _RefundRequestEditSheet extends StatefulWidget {
  const _RefundRequestEditSheet({required this.paymentDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> paymentDoc;

  @override
  State<_RefundRequestEditSheet> createState() => _RefundRequestEditSheetState();
}

class _RefundRequestEditSheetState extends State<_RefundRequestEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final LayerLink _verifiedFieldLink = LayerLink();
  final GlobalKey _verifiedFieldKey = GlobalKey();
  OverlayEntry? _verifiedOverlayEntry;

  late final TextEditingController _paymentIdCtrl;
  late final TextEditingController _verifiedCtrl;
  late final TextEditingController _receiptFileCtrl;

  bool _verifiedValue = false;
  bool _saving = false;

  Uint8List? _selectedReceiptBytes;
  String? _existingReceiptUrl;
  String? _existingReceiptStoragePath;

  static const _verifiedOptions = <_VerifiedOption>[
    _VerifiedOption(label: 'Verified', value: true),
    _VerifiedOption(label: 'Unverified', value: false),
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.paymentDoc.data();
    _paymentIdCtrl = TextEditingController(text: widget.paymentDoc.id);
    _verifiedValue = data['verified'] == true;
    _verifiedCtrl = TextEditingController(
      text: _verifiedValue ? 'Verified' : 'Unverified',
    );
    _receiptFileCtrl = TextEditingController(
      text: ((data['receiptFileName'] as String?) ?? '').trim(),
    );
    _existingReceiptUrl = (data['receiptUrl'] as String?)?.trim();
    _existingReceiptStoragePath = (data['receiptStoragePath'] as String?)?.trim();
  }

  @override
  void dispose() {
    _closeVerifiedMenu();
    _paymentIdCtrl.dispose();
    _verifiedCtrl.dispose();
    _receiptFileCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
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
        borderSide: BorderSide(color: _primaryBlue, width: 1.2),
      ),
      suffixIcon: suffixIcon,
    );
  }

  void _toggleVerifiedMenu() {
    if (_verifiedOverlayEntry != null) {
      _closeVerifiedMenu();
      return;
    }
    final overlay = Overlay.of(context);

    final renderBox =
        _verifiedFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldSize = renderBox?.size ?? const Size(0, 0);
    final fieldOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = overlayBox?.size ?? const Size(0, 0);

    const desiredHeight = 120.0;
    const margin = 10.0;
    final belowY = fieldOffset.dy + fieldSize.height + 8;
    final canShowBelow = belowY + desiredHeight <= overlaySize.height - margin;
    final showBelow = canShowBelow || fieldOffset.dy < overlaySize.height / 2;

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
                  offset: showBelow
                      ? Offset(0, fieldSize.height + 8)
                      : Offset(0, -(desiredHeight + 8)),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: fieldSize.width,
                      height: desiredHeight,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          for (final option in _verifiedOptions)
                            InkWell(
                              onTap: () => _selectVerified(option),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: option.value == _verifiedValue
                                      ? _primaryBlue.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        option.label,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: _profileDarkText,
                                        ),
                                      ),
                                    ),
                                    if (option.value == _verifiedValue)
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: _primaryBlue,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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
      _verifiedValue = option.value;
      _verifiedCtrl.text = option.label;
    });
    _closeVerifiedMenu();
  }

  Future<void> _pickReceiptFile() async {
    final pdfGroup = const XTypeGroup(label: 'pdf', extensions: ['pdf']);
    final picked = await openFile(
      acceptedTypeGroups: [pdfGroup],
      confirmButtonText: 'Select',
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() {
      _selectedReceiptBytes = bytes;
      _receiptFileCtrl.text = picked.name;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      final data = widget.paymentDoc.data();
      final userId = ((data['userId'] as String?) ?? '').trim();
      String? receiptUrl = _existingReceiptUrl;
      String? receiptStoragePath = _existingReceiptStoragePath;

      if (_selectedReceiptBytes != null) {
        final uploadPath = 'refundReceipts/$userId/${widget.paymentDoc.id}.pdf';
        final ref = FirebaseStorage.instance.ref(uploadPath);
        await ref.putData(
          _selectedReceiptBytes!,
          SettableMetadata(contentType: 'application/pdf'),
        );
        receiptUrl = await ref.getDownloadURL();
        if (receiptStoragePath != null &&
            receiptStoragePath.isNotEmpty &&
            receiptStoragePath != uploadPath) {
          await FirebaseStorage.instance
              .ref(receiptStoragePath)
              .delete()
              .catchError((_) {});
        }
        receiptStoragePath = uploadPath;
      }

      final receiptFileName = _receiptFileCtrl.text.trim();
      await widget.paymentDoc.reference.set({
        'verified': _verifiedValue,
        if (_verifiedValue) 'verifiedAt': FieldValue.serverTimestamp(),
        if (!_verifiedValue) 'verifiedAt': FieldValue.delete(),
        if (receiptFileName.isNotEmpty) 'receiptFileName': receiptFileName,
        if (receiptFileName.isEmpty) 'receiptFileName': FieldValue.delete(),
        if (receiptUrl != null && receiptUrl.trim().isNotEmpty)
          'receiptUrl': receiptUrl.trim(),
        if (receiptUrl == null || receiptUrl.trim().isEmpty)
          'receiptUrl': FieldValue.delete(),
        if (receiptStoragePath != null && receiptStoragePath.trim().isNotEmpty)
          'receiptStoragePath': receiptStoragePath.trim(),
        if (receiptStoragePath == null || receiptStoragePath.trim().isEmpty)
          'receiptStoragePath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final data = widget.paymentDoc.data();
    final userId = ((data['userId'] as String?) ?? '').trim();
    final userRef = userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(userId);
    final amount = _readMoney(data['amount']);
    final netAmount = _refundNetAmount(amount);

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
                          'Refund request',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: userRef?.get(),
                    builder: (context, snapshot) {
                      final userData = snapshot.data?.data();
                      final userName =
                          (userData?['name'] as String?)?.trim() ?? userId;
                      final userPhoto =
                          (userData?['profile_photo'] as String?)?.trim() ??
                              (userData?['photoUrl'] as String?)?.trim();
                      return Column(
                        children: [
                          DefaultProfileAvatar(
                            radius: 34,
                            photoUrl:
                                userPhoto?.isNotEmpty == true ? userPhoto : null,
                            label: userName.isNotEmpty ? userName : '?',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            userName.isNotEmpty ? userName : 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: _profileDarkText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (userId.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              userId,
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
                    controller: _paymentIdCtrl,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration('Payment ID'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Refund details',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue:
                        netAmount > 0
                            ? 'RM ${netAmount.toStringAsFixed(2)}'
                            : '-',
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration('Refund amount'),
                  ),
                  const SizedBox(height: 10),
                  CompositedTransformTarget(
                    link: _verifiedFieldLink,
                    child: TextFormField(
                      key: _verifiedFieldKey,
                      controller: _verifiedCtrl,
                      readOnly: true,
                      showCursor: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                      decoration: _fieldDecoration(
                        'Verified',
                        suffixIcon: const Icon(Icons.expand_more, size: 18),
                      ),
                      onTap: _saving ? null : _toggleVerifiedMenu,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _receiptFileCtrl,
                    readOnly: true,
                    showCursor: false,
                    onTap: _saving ? null : _pickReceiptFile,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: _fieldDecoration(
                      'Receipt file',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.upload_file, size: 18),
                        onPressed: _saving ? null : _pickReceiptFile,
                      ),
                    ),
                    validator: (_) {
                      if (!_verifiedValue) return null;
                      final hasExisting =
                          (_existingReceiptUrl ?? '').trim().isNotEmpty;
                      final hasSelected = _selectedReceiptBytes != null;
                      if (!hasExisting && !hasSelected) {
                        return 'Upload receipt to mark as verified.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF only. Receipt will be stored on this refund request.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4B63D),
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

/*
class _WithdrawRequestsTab extends StatelessWidget {
  const _WithdrawRequestsTab({required this.tabIndexListenable});

  final ValueListenable<int> tabIndexListenable;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('withdrawRequests')
        .orderBy('requestedAt', descending: true)
        .limit(200)
        .snapshots();

    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: 0,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return buildAdminEmptyState(
              icon: Icons.payments_outlined,
              title: 'Unable to load withdrawals',
              subtitle: 'Please try again.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return buildAdminEmptyState(
              icon: Icons.payments_outlined,
              title: 'No withdrawal requests',
              subtitle: 'New requests will appear here.',
            );
          }

          final entries = docs.map(_WithdrawRequestEntry.fromDoc).toList();
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _VerificationRowCard(
                leadingIcon: Icons.payments_outlined,
                title: entry.caregiverId,
                subtitle: [
                  if (entry.status.isNotEmpty) 'Status: ${entry.status}',
                  if (entry.payoutAmount > 0)
                    'Amount: RM ${entry.payoutAmount.toStringAsFixed(2)}',
                  if (entry.requestedAt != null)
                    _adminDateFormat.format(entry.requestedAt!.toDate()),
                ].join(' • '),
                onTap: () => _openPayoutAccountSheet(
                  context,
                  title: 'Withdraw request',
                  targetRef: FirebaseFirestore.instance
                      .collection('caregivers')
                      .doc(entry.caregiverId),
                  requestDetails: [
                    _KeyValueRow(label: 'Request ID', value: entry.requestId),
                    _KeyValueRow(
                      label: 'Caregiver ID',
                      value: entry.caregiverId,
                    ),
                    _KeyValueRow(label: 'Status', value: entry.status),
                    _KeyValueRow(
                      label: 'Requested amount',
                      value: entry.payoutAmount > 0
                          ? 'RM ${entry.payoutAmount.toStringAsFixed(2)}'
                          : 'Unavailable',
                    ),
                    _KeyValueRow(
                      label: 'Requested at',
                      value: entry.requestedAt == null
                          ? 'Unavailable'
                          : _adminDateFormat.format(
                              entry.requestedAt!.toDate(),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RefundRequestsTab extends StatelessWidget {
  const _RefundRequestsTab({required this.tabIndexListenable});

  final ValueListenable<int> tabIndexListenable;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('payments')
        .where('paymentStatus', whereIn: const ['REFUND_REQUESTED', 'REFUNDED'])
        .limit(200)
        .snapshots();

    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: 1,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return buildAdminEmptyState(
              icon: Icons.currency_exchange_outlined,
              title: 'Unable to load refunds',
              subtitle: 'Please try again.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return buildAdminEmptyState(
              icon: Icons.currency_exchange_outlined,
              title: 'No refund requests',
              subtitle: 'New refunds will appear here.',
            );
          }

          final entries =
              docs
                  .map(_RefundPaymentEntry.fromDoc)
                  .where((e) => e.userId.trim().isNotEmpty)
                  .toList()
                ..sort(
                  (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
                      .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
                );

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _VerificationRowCard(
                leadingIcon: Icons.currency_exchange_outlined,
                title: entry.userId,
                subtitle: [
                  if (entry.paymentStatus.isNotEmpty)
                    'Status: ${entry.paymentStatus}',
                  if (entry.amount > 0)
                    'Amount: RM ${entry.amount.toStringAsFixed(2)}',
                  if (entry.createdAt != null)
                    _adminDateFormat.format(entry.createdAt!.toDate()),
                ].join(' • '),
                onTap: () => _openPayoutAccountSheet(
                  context,
                  title: 'Refund request',
                  targetRef: FirebaseFirestore.instance
                      .collection('users')
                      .doc(entry.userId),
                  requestDetails: [
                    _KeyValueRow(label: 'Payment ID', value: entry.paymentId),
                    _KeyValueRow(label: 'Booking ID', value: entry.bookingId),
                    _KeyValueRow(label: 'User ID', value: entry.userId),
                    _KeyValueRow(
                      label: 'Payment status',
                      value: entry.paymentStatus,
                    ),
                    _KeyValueRow(
                      label: 'Amount',
                      value: entry.amount > 0
                          ? 'RM ${entry.amount.toStringAsFixed(2)}'
                          : 'Unavailable',
                    ),
                    _KeyValueRow(
                      label: 'Created at',
                      value: entry.createdAt == null
                          ? 'Unavailable'
                          : _adminDateFormat.format(entry.createdAt!.toDate()),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _openPayoutAccountSheet(
  BuildContext context, {
  required String title,
  required DocumentReference<Map<String, dynamic>> targetRef,
  required List<_KeyValueRow> requestDetails,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PayoutAccountDetailsSheet(
      title: title,
      targetRef: targetRef,
      requestDetails: requestDetails,
    ),
  );
}

class _VerificationRowCard extends StatelessWidget {
  const _VerificationRowCard({
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: activityAccentBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: activityAccentBlue.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(leadingIcon, size: 18, color: activityAccentBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.trim().isEmpty ? 'Unavailable' : title.trim(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _profileDarkText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.trim().isEmpty ? 'Unavailable' : subtitle.trim(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
*/

class _PayoutAccountDetailsSheet extends StatefulWidget {
  const _PayoutAccountDetailsSheet({
    required this.title,
    required this.targetRef,
    required this.requestDetails,
  });

  final String title;
  final DocumentReference<Map<String, dynamic>> targetRef;
  final List<_KeyValueRow> requestDetails;

  @override
  State<_PayoutAccountDetailsSheet> createState() =>
      _PayoutAccountDetailsSheetState();
}

class _PayoutAccountDetailsSheetState
    extends State<_PayoutAccountDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _bankController = TextEditingController();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _bankController.dispose();
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  void _applyPaymentDetails(Map<String, dynamic>? raw) {
    if (_loaded) return;
    _loaded = true;
    final details = (raw?['paymentDetails'] as Map?)?.cast<String, dynamic>();
    _bankController.text = (details?['bankName'] as String?)?.trim() ?? '';
    _nameController.text = (details?['accountName'] as String?)?.trim() ?? '';
    _numberController.text =
        (details?['accountNumber'] as String?)?.trim() ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.targetRef.set({
        'paymentDetails': {
          'bankName': _bankController.text.trim(),
          'accountName': _nameController.text.trim(),
          'accountNumber': _numberController.text.trim(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await widget.targetRef.set({
        'paymentDetails': FieldValue.delete(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: widget.targetRef.snapshots(),
                builder: (context, snapshot) {
                  _applyPaymentDetails(snapshot.data?.data());
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              height: 4,
                              width: 44,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _profileDarkText,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _SheetSection(title: 'Request details'),
                          const SizedBox(height: 10),
                          _KeyValueTable(rows: widget.requestDetails),
                          const SizedBox(height: 14),
                          _SheetSection(title: 'Payout account'),
                          const SizedBox(height: 10),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _SheetField(
                                  label: 'Bank name',
                                  controller: _bankController,
                                ),
                                const SizedBox(height: 10),
                                _SheetField(
                                  label: 'Account holder',
                                  controller: _nameController,
                                ),
                                const SizedBox(height: 10),
                                _SheetField(
                                  label: 'Account number',
                                  controller: _numberController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _clear,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: BorderSide(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text(
                                    'Delete payout account',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _saving ? null : _save,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFFF4B63D),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(
                                    _saving ? 'Saving...' : 'Save',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: _profileDarkText,
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _profileDarkText,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Required';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _profileDarkText.withValues(alpha: 0.70),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: activityAccentBlue.withValues(alpha: 0.40),
          ),
        ),
      ),
    );
  }
}

class _KeyValueRow {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _KeyValueTable extends StatelessWidget {
  const _KeyValueTable({required this.rows});

  final List<_KeyValueRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          final isLast = index == rows.length - 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText.withValues(alpha: 0.70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.value.trim().isEmpty ? 'Unavailable' : row.value,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _profileDarkText,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Divider(
                  height: 14,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _WithdrawRequestEntry {
  const _WithdrawRequestEntry({
    required this.requestId,
    required this.caregiverId,
    required this.status,
    required this.payoutAmount,
    required this.requestedAt,
  });

  final String requestId;
  final String caregiverId;
  final String status;
  final double payoutAmount;
  final Timestamp? requestedAt;

  factory _WithdrawRequestEntry.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _WithdrawRequestEntry(
      requestId: doc.id,
      caregiverId: (data['caregiverId'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? '',
      payoutAmount: _readMoney(data['payoutAmount']),
      requestedAt: data['requestedAt'] as Timestamp?,
    );
  }
}

class _RefundPaymentEntry {
  const _RefundPaymentEntry({
    required this.paymentId,
    required this.userId,
    required this.bookingId,
    required this.paymentStatus,
    required this.amount,
    required this.createdAt,
  });

  final String paymentId;
  final String userId;
  final String bookingId;
  final String paymentStatus;
  final double amount;
  final Timestamp? createdAt;

  factory _RefundPaymentEntry.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _RefundPaymentEntry(
      paymentId: doc.id,
      userId: (data['userId'] as String?)?.trim() ?? '',
      bookingId: (data['bookingId'] as String?)?.trim() ?? '',
      paymentStatus: (data['paymentStatus'] as String?)?.trim() ?? '',
      amount: _readMoney(data['amount']),
      createdAt:
          (data['updatedAt'] as Timestamp?) ??
          (data['createdAt'] as Timestamp?) ??
          (data['paidAt'] as Timestamp?),
    );
  }
}

double _readMoney(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
  return 0.0;
}

({double serviceFee, double platformFee, double netAmount}) _withdrawNetBreakdown(
  double requestedAmount,
) {
  // Admin requests should reflect the full payout amount (no deductions).
  return (serviceFee: 0.0, platformFee: 0.0, netAmount: requestedAmount.clamp(0.0, double.infinity));
}

double _refundNetAmount(double amount) {
  // Refund amount should reflect the original paid amount (no deductions).
  return amount.clamp(0.0, double.infinity);
}

String _formatRm(double amount) {
  if (amount <= 0) return '-';
  return 'RM ${amount.toStringAsFixed(2)}';
}
