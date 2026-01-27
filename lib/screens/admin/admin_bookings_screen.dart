import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' show lerpDouble;
import 'dart:io' show File, Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../ui_tokens.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_tracking_helpers.dart' show normalizeString;
import '../../utils/service_preferences.dart'
    show extractServiceLabelFromFirestore, extractServicePreferencesList;
import '../caregiver/profile/profile_availability_shared.dart'
    show
        availabilityPickerBuilder;
import '../user/activity/activity_screen.dart'
    show activityBackgroundColor, activityButtonYellow;
import 'admin_ui.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _profileDarkText60 = Color(0x991B1D29);
const Color _tealAccent = Color(0xFF00A8A7);
const Color _primaryBlue = Color(0xFF00A8A7);

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

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

const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);

class AdminBookingsScreen extends StatelessWidget {
  const AdminBookingsScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 1,
    this.initialTabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    final content = _AdminBookingsDashboard(initialTabIndex: initialTabIndex);
    if (tabIndexListenable == null) return content;
    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: tabIndex,
      child: content,
    );
  }
}

enum _AdminBookingsMode { bookings, payments }

enum _BookingsStatusFilter {
  all,
  assigned,
  ongoing,
  completed,
  cancelled,
  missing,
}

enum _PaymentsStatusFilter { all, paid, pending }

class _AdminBookingsDashboard extends StatefulWidget {
  const _AdminBookingsDashboard({required this.initialTabIndex});

  final int initialTabIndex;

  @override
  State<_AdminBookingsDashboard> createState() =>
      _AdminBookingsDashboardState();
}

class _AdminBookingsDashboardState extends State<_AdminBookingsDashboard> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  late _AdminBookingsMode _mode;
  _BookingsStatusFilter _bookingsFilter = _BookingsStatusFilter.all;
  _PaymentsStatusFilter _paymentsFilter = _PaymentsStatusFilter.all;
  late DateTime _selectedMonth;
  double _sheetExtent = 0;
  bool _modalSheetScrimVisible = false;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  @override
  void initState() {
    super.initState();
    final initialTab = widget.initialTabIndex.clamp(0, 1);
    _mode = initialTab == 1
        ? _AdminBookingsMode.payments
        : _AdminBookingsMode.bookings;
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    setState(() => _searchText = _searchController.text.trim());
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

  Future<void> _generateMonthlyReport() async {
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
      final callableName = _mode == _AdminBookingsMode.payments
          ? 'generateAdminPaymentsReport'
          : 'generateAdminBookingsReport';
      final callable = _functions.httpsCallable(callableName);
      final result = await callable.call(<String, dynamic>{
        'year': month.year,
        'month': month.month,
      });

      closeLoadingIfOpen();

      final data = (result.data as Map).cast<String, dynamic>();
      final pdfBase64 = (data['pdfBase64'] as String?) ?? '';
      final fileName =
          (data['fileName'] as String?) ??
          (_mode == _AdminBookingsMode.payments
              ? 'payments-report.pdf'
              : 'bookings-report.pdf');
      if (pdfBase64.trim().isEmpty) return;

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
                        try {
                          await Share.shareXFiles([
                            XFile(
                              path,
                              mimeType: 'application/pdf',
                              name: fileName,
                            ),
                          ], subject: fileName);
                        } catch (_) {}
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

  void _setBookingsFilter(_BookingsStatusFilter filter) {
    if (_bookingsFilter == filter) return;
    setState(() => _bookingsFilter = filter);
  }

  void _setPaymentsFilter(_PaymentsStatusFilter filter) {
    if (_paymentsFilter == filter) return;
    setState(() => _paymentsFilter = filter);
  }

  @override
  Widget build(BuildContext context) {
    final isPayments = _mode == _AdminBookingsMode.payments;
    final monthLabel = _monthLabel(_selectedMonth);
    final monthRange = _monthRange(_selectedMonth);
    final monthStartTs = Timestamp.fromDate(monthRange.start);
    final monthEndTs = Timestamp.fromDate(monthRange.end);

    final monthBookingsStream = FirebaseFirestore.instance
        .collection('bookings')
        .where('createdAt', isGreaterThanOrEqualTo: monthStartTs)
        .where('createdAt', isLessThan: monthEndTs)
        .limit(500)
        .snapshots();

    final monthPaymentsStream = FirebaseFirestore.instance
        .collection('payments')
        .where('createdAt', isGreaterThanOrEqualTo: monthStartTs)
        .where('createdAt', isLessThan: monthEndTs)
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
            child: _BookingsAnalyticsCard(
              mode: _mode,
              monthLabel: monthLabel,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onGenerateReport: _generateMonthlyReport,
              monthBookingsStream: monthBookingsStream,
              monthPaymentsStream: monthPaymentsStream,
            ),
          ),
        ],
      ),
    );

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panelMinExtent = () {
      final screenHeight = MediaQuery.of(context).size.height;
      final headerHeight = _heroHeight + _headerCardOverlap;
      final desiredTopGap = 12.0;
      return ((screenHeight - (headerHeight + desiredTopGap)) / screenHeight)
          .clamp(0.30, 0.70)
          .toDouble();
    }();

    final effectiveExtent = _sheetExtent <= 0 ? panelMinExtent : _sheetExtent;
    final denom = (_panelMaxExtent - panelMinExtent).clamp(0.0001, 1.0);
    final t = ((effectiveExtent - panelMinExtent) / denom).clamp(0.0, 1.0);
    final panelBackdropAlpha = (lerpDouble(0.0, 0.08, t) ?? 0.0)
        .clamp(0.0, 0.12)
        .toDouble();
    final appBarT = ((effectiveExtent - 0.90) / 0.10)
        .clamp(0.0, 1.0)
        .toDouble();
    final topChromeInset = (lerpDouble(0, kToolbarHeight + 6.0, appBarT) ?? 0.0)
        .clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: buildProfileStyleAppBar(
        title: isPayments ? 'Payments' : 'Bookings',
      ),
      body: Stack(
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
          Positioned.fill(
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
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              final next = notification.extent;
              if ((next - _sheetExtent).abs() < 0.0005) return false;
              setState(() => _sheetExtent = next);
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: panelMinExtent,
              minChildSize: panelMinExtent,
              maxChildSize: _panelMaxExtent,
              builder: (sheetContext, controller) {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      (bottomInset + 24).clamp(24.0, 64.0),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 22,
                          offset: const Offset(0, -10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: topChromeInset),
                        SizedBox(
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
                        Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView(
                            controller: controller,
                            padding: EdgeInsets.zero,
                            physics: const ClampingScrollPhysics(),
                            children: [
                              _SearchField(
                                controller: _searchController,
                                hintText: isPayments
                                    ? 'Search payment'
                                    : 'Search booking',
                              ),
                              const SizedBox(height: 10),
                              if (isPayments)
                                _PaymentsFilterBar(
                                  selected: _paymentsFilter,
                                  onSelected: _setPaymentsFilter,
                                )
                              else
                                _BookingsFilterBar(
                                  selected: _bookingsFilter,
                                  onSelected: _setBookingsFilter,
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: isPayments
                                    ? _PaymentsTab(
                                        searchText: _searchText,
                                        filter: _paymentsFilter,
                                      )
                                    : _BookingsTab(
                                        searchText: _searchText,
                                        filter: _bookingsFilter,
                                        onView: _openBookingDetails,
                                        onEdit: _openEditSheet,
                                        onDelete: _deleteBooking,
                                        onChangeStatus: (ref, status) =>
                                            _setBookingStatus(
                                              ref,
                                              status: status,
                                            ),
                                      ),
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

  Future<void> _openBookingDetails(_BookingEntry entry) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => _BookingDetailsSheet(entry: entry),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _setBookingStatus(
    DocumentReference<Map<String, dynamic>> ref, {
    required String status,
  }) async {
    try {
      await ref.set({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Updated status to $status.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update status. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openEditSheet(
    DocumentSnapshot<Map<String, dynamic>> booking,
  ) async {
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdminBookingEditSheet(booking: booking),
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _deleteBooking(
    DocumentSnapshot<Map<String, dynamic>> booking,
  ) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: activityBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this booking?',
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
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await booking.reference.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking deleted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete booking. Please try again.'),
        ),
      );
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

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
        hintText: hintText,
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

class _BookingsFilterBar extends StatelessWidget {
  const _BookingsFilterBar({required this.selected, required this.onSelected});

  final _BookingsStatusFilter selected;
  final ValueChanged<_BookingsStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _BookingsStatusFilter.assigned
        ? 'Assigned bookings'
        : selected == _BookingsStatusFilter.ongoing
        ? 'Ongoing bookings'
        : selected == _BookingsStatusFilter.completed
        ? 'Completed bookings'
        : selected == _BookingsStatusFilter.cancelled
        ? 'Cancelled bookings'
        : selected == _BookingsStatusFilter.missing
        ? 'Missing bookings'
        : 'All bookings';

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
                    selected: selected == _BookingsStatusFilter.all,
                    onTap: () => onSelected(_BookingsStatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Assigned',
                    selected: selected == _BookingsStatusFilter.assigned,
                    onTap: () => onSelected(_BookingsStatusFilter.assigned),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Ongoing',
                    selected: selected == _BookingsStatusFilter.ongoing,
                    onTap: () => onSelected(_BookingsStatusFilter.ongoing),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Completed',
                    selected: selected == _BookingsStatusFilter.completed,
                    onTap: () => onSelected(_BookingsStatusFilter.completed),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Cancelled',
                    selected: selected == _BookingsStatusFilter.cancelled,
                    onTap: () => onSelected(_BookingsStatusFilter.cancelled),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Missing',
                    selected: selected == _BookingsStatusFilter.missing,
                    onTap: () => onSelected(_BookingsStatusFilter.missing),
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

class _PaymentsFilterBar extends StatelessWidget {
  const _PaymentsFilterBar({required this.selected, required this.onSelected});

  final _PaymentsStatusFilter selected;
  final ValueChanged<_PaymentsStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _PaymentsStatusFilter.paid
        ? 'Paid payments'
        : selected == _PaymentsStatusFilter.pending
        ? 'Pending payments'
        : 'All payments';

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
                    selected: selected == _PaymentsStatusFilter.all,
                    onTap: () => onSelected(_PaymentsStatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Paid',
                    selected: selected == _PaymentsStatusFilter.paid,
                    onTap: () => onSelected(_PaymentsStatusFilter.paid),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Pending',
                    selected: selected == _PaymentsStatusFilter.pending,
                    onTap: () => onSelected(_PaymentsStatusFilter.pending),
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

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({
    required this.searchText,
    required this.filter,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onChangeStatus,
  });

  final String searchText;
  final _BookingsStatusFilter filter;
  final ValueChanged<_BookingEntry> onView;
  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onEdit;
  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onDelete;
  final void Function(
    DocumentReference<Map<String, dynamic>> ref,
    String status,
  )
  onChangeStatus;

  static String _pickText(Object? v) => (v?.toString() ?? '').trim();

  static double _pickNum(Object? v) {
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(_pickText(v));
    return parsed ?? 0;
  }

  static DateTime? _pickDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static bool _isEmergencyAlert(Map<String, dynamic> data) {
    final status = _pickText(
      data['status'],
    ).trim().toUpperCase().replaceAll(' ', '_');
    if (status == 'EMERGENCY_ALERT') return true;
    final service = _pickText(
      data['service'] ?? data['type'] ?? data['title'],
    ).trim().toUpperCase().replaceAll(' ', '_');
    return service == 'EMERGENCY_ALERT';
  }

  static String _formatCurrency(num value) {
    final v = value.toDouble();
    return 'RM ${v.toStringAsFixed(2)}';
  }

  static Color _statusDot(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'scheduled' ||
        normalized == 'pending' ||
        normalized == 'ready') {
      return const Color(0xFFF4B63D);
    }
    if (normalized == 'ongoing' ||
        normalized == 'in_progress' ||
        normalized == 'notify' ||
        normalized == 'handle_client') {
      return Colors.blue.shade700;
    }
    if (normalized == 'completed' || normalized == 'paid') {
      return Colors.green.shade700;
    }
    if (normalized == 'cancelled' ||
        normalized == 'canceled' ||
        normalized == 'failed') {
      return Colors.red.shade700;
    }
    if (normalized == 'emergency' || normalized == 'emergency_alert') {
      return Colors.red.shade700;
    }
    return Colors.grey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('bookings')
        .orderBy('createdAt', descending: true)
        .limit(160)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            height: 320,
            child: buildAdminEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Unable to load bookings',
              subtitle: 'Please try again.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs;
        final entries =
            docs
                .where((doc) {
                  return !_isEmergencyAlert(doc.data());
                })
                .map((doc) {
                  final data = doc.data();
                  final id = doc.id;
                  final status = _pickText(data['status']);
                  final title = _pickText(
                    data['service'] ?? data['type'] ?? data['title'],
                  );
                  final date = _pickText(data['scheduledDate'] ?? data['date']);
                  final paymentMethod = _pickText(data['paymentMethod']);
                  final servicePrice = _pickNum(data['servicePrice']);
                  final createdAt = _pickDate(
                    data['createdAt'] ?? data['created_at'],
                  );

                  return _BookingEntry(
                    booking: doc,
                    id: id,
                    status: status,
                    title: title,
                    subtitle: date,
                    paymentMethod: paymentMethod,
                    servicePrice: servicePrice,
                    createdAt: createdAt,
                    userId: _pickText(data['userId'] ?? data['ownerUserId']),
                    caregiverId: _pickText(data['caregiverId']),
                    caregiverName: _pickText(data['caregiverName']),
                    personName: _pickText(data['personName']),
                    personAddress: _pickText(data['personAddress']),
                    toyyibBillCode: _pickText(
                      data['toyyibBillCode'] ?? data['billCode'],
                    ),
                    rawData: Map<String, dynamic>.from(data),
                  );
                })
                .toList()
              ..sort((a, b) {
                final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                return bt.compareTo(at);
              });

        final search = searchText.trim().toLowerCase();
        final filtered = entries
            .where((e) {
              if (search.isEmpty) return true;
              if (e.id.toLowerCase().contains(search)) return true;
              if (e.title.toLowerCase().contains(search)) return true;
              if (e.subtitle.toLowerCase().contains(search)) return true;
              return e.status.toLowerCase().contains(search) ||
                  e.paymentMethod.toLowerCase().contains(search);
            })
            .where((e) {
              if (filter == _BookingsStatusFilter.all) return true;
              final normalized = e.status.trim().toUpperCase().replaceAll(
                ' ',
                '_',
              );
              final caregiverMissing = e.caregiverId.trim().isEmpty;
              final isMissing =
                  normalized.isEmpty ||
                  normalized == 'UNKNOWN' ||
                  normalized == 'MISSING' ||
                  caregiverMissing;
              final isAssigned =
                  normalized == 'ASSIGNED' ||
                  normalized == 'SCHEDULED' ||
                  normalized == 'READY';
              final isOngoing =
                  normalized == 'ONGOING' ||
                  normalized == 'IN_PROGRESS' ||
                  normalized == 'HANDLE_CLIENT' ||
                  normalized == 'NOTIFY';
              final isCompleted =
                  normalized == 'COMPLETED' ||
                  normalized == 'PAID' ||
                  normalized == 'DONE';
              final isCancelled =
                  normalized == 'CANCELLED' ||
                  normalized == 'CANCELED' ||
                  normalized == 'FAILED';

              if (filter == _BookingsStatusFilter.assigned) return isAssigned;
              if (filter == _BookingsStatusFilter.ongoing) return isOngoing;
              if (filter == _BookingsStatusFilter.completed) return isCompleted;
              if (filter == _BookingsStatusFilter.cancelled) return isCancelled;
              return isMissing;
            })
            .toList(growable: false);

        if (filtered.isEmpty) {
          return SizedBox(
            height: 320,
            child: buildAdminEmptyState(
              icon: Icons.search_off_outlined,
              title: 'No results',
              subtitle: 'Try a different keyword.',
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = filtered[index];
            final payment = entry.paymentMethod.trim().isNotEmpty
                ? entry.paymentMethod.trim()
                : '-';
            final priceLabel = entry.servicePrice > 0
                ? _formatCurrency(entry.servicePrice)
                : '-';
            return _BookingDocCard(
              indexNumber: index + 1,
              booking: entry.booking,
              caregiverId: entry.caregiverId,
              caregiverNameHint: entry.caregiverName,
              serviceTitle: entry.title.trim().isNotEmpty
                  ? entry.title.trim()
                  : 'Booking',
              status: entry.status.trim().isNotEmpty
                  ? entry.status.trim()
                  : 'UNKNOWN',
              dotColor: _statusDot(entry.status),
              bookingId: entry.id,
              date: entry.subtitle.trim().isNotEmpty
                  ? entry.subtitle.trim()
                  : '-',
              paymentMethod: payment,
              servicePriceLabel: priceLabel,
              onView: () => onView(entry),
              onEdit: () => onEdit(entry.booking),
              onDelete: () => onDelete(entry.booking),
              onChangeStatus: (next) =>
                  onChangeStatus(entry.booking.reference, next),
            );
          },
        );
      },
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.searchText, required this.filter});

  final String searchText;
  final _PaymentsStatusFilter filter;

  static String _pickText(Object? v) => (v?.toString() ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .limit(160)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            height: 320,
            child: buildAdminEmptyState(
              icon: Icons.payments_outlined,
              title: 'Unable to load payments',
              subtitle: 'Please try again.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs;
        final search = searchText.trim().toLowerCase();
        final filtered = docs
            .where((d) {
              if (search.isEmpty) return true;
              if (d.id.toLowerCase().contains(search)) return true;
              final data = d.data();
              final bookingId = _pickText(data['bookingId']).toLowerCase();
              final method = _pickText(data['paymentMethod']).toLowerCase();
              return bookingId.contains(search) || method.contains(search);
            })
            .where((d) {
              if (filter == _PaymentsStatusFilter.all) return true;
              final raw = _pickText(
                d.data()['paymentStatus'] ?? d.data()['status'],
              );
              final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
              final isPaid = normalized == '1' || normalized == 'PAID';
              if (filter == _PaymentsStatusFilter.paid) return isPaid;
              return !isPaid;
            })
            .toList(growable: false);

        if (filtered.isEmpty) {
          return SizedBox(
            height: 320,
            child: buildAdminEmptyState(
              icon: Icons.search_off_outlined,
              title: 'No results',
              subtitle: 'Try a different keyword.',
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final data = doc.data();
            final bookingId = _pickText(data['bookingId']);
            final method = _pickText(data['paymentMethod']);
            return _PaymentDocCard(
              indexNumber: index + 1,
              paymentId: doc.id,
              bookingId: bookingId,
              paymentMethod: method,
              rawStatus: _pickText(data['paymentStatus'] ?? data['status']),
            );
          },
        );
      },
    );
  }
}

class _BookingEntry {
  const _BookingEntry({
    required this.booking,
    required this.id,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.paymentMethod,
    required this.servicePrice,
    required this.createdAt,
    required this.userId,
    required this.caregiverId,
    required this.caregiverName,
    required this.personName,
    required this.personAddress,
    required this.toyyibBillCode,
    required this.rawData,
  });

  final DocumentSnapshot<Map<String, dynamic>> booking;
  final String id;
  final String status;
  final String title;
  final String subtitle;
  final String paymentMethod;
  final double servicePrice;
  final DateTime? createdAt;
  final String userId;
  final String caregiverId;
  final String caregiverName;
  final String personName;
  final String personAddress;
  final String toyyibBillCode;
  final Map<String, dynamic> rawData;
}

class _BookingDocCard extends StatelessWidget {
  const _BookingDocCard({
    required this.indexNumber,
    required this.booking,
    required this.caregiverId,
    required this.caregiverNameHint,
    required this.serviceTitle,
    required this.status,
    required this.dotColor,
    required this.bookingId,
    required this.date,
    required this.paymentMethod,
    required this.servicePriceLabel,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onChangeStatus,
  });

  final int indexNumber;
  final DocumentSnapshot<Map<String, dynamic>> booking;
  final String caregiverId;
  final String caregiverNameHint;
  final String serviceTitle;
  final String status;
  final Color dotColor;
  final String bookingId;
  final String date;
  final String paymentMethod;
  final String servicePriceLabel;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onChangeStatus;

  static String _chipLabel(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
    if (normalized.isEmpty) return 'Unknown';
    if (normalized == 'SCHEDULED') return 'Scheduled';
    if (normalized == 'ASSIGNED') return 'Assigned';
    if (normalized == 'ONGOING' || normalized == 'IN_PROGRESS') return 'Ongoing';
    if (normalized == 'COMPLETED') return 'Completed';
    if (normalized == 'CANCELLED' || normalized == 'CANCELED') return 'Cancelled';
    if (normalized == 'FAILED') return 'Failed';
    return raw.trim();
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
      child: Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: 0.85,
          child: Container(height: 1.2, color: Colors.black.withAlpha(20)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caregiverRef = caregiverId.trim().isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('caregivers')
              .doc(caregiverId.trim());
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
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: caregiverRef?.get(),
            builder: (context, snapshot) {
              final caregiverData = snapshot.data?.data();
              final caregiverName =
                  (caregiverData?['name'] as String?)?.trim() ??
                  caregiverNameHint.trim();
              final caregiverPhoto =
                  (caregiverData?['profile_photo'] as String?)?.trim() ??
                  (caregiverData?['photoUrl'] as String?)?.trim();

              final displayName = caregiverName.isNotEmpty
                  ? caregiverName
                  : (caregiverId.trim().isNotEmpty
                        ? caregiverId.trim()
                        : 'Caregiver');

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
                            label: displayName.isNotEmpty ? displayName : '?',
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
                                  onSelected: onChangeStatus,
                                  itemBuilder: (context) =>
                                      _bookingStatusMenuItems(current: status),
                                  child: _CompactStatusChip(
                                    label: _chipLabel(status),
                                    dotColor: dotColor,
                                    maxLabelWidth: 72,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: UiTokens.s4),
                            Text(
                              serviceTitle,
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
                  Row(
                    children: [
                      Text(
                        'Booking ID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withValues(alpha: 0.50),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bookingId.trim().isNotEmpty ? bookingId.trim() : '-',
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
                  const SizedBox(height: UiTokens.s6),
                  Text('Date: $date', style: _documentMetaStyle),
                  const SizedBox(height: UiTokens.s2),
                  Text('Payment: $paymentMethod', style: _documentMetaStyle),
                  const SizedBox(height: UiTokens.s2),
                  Text(
                    'Service price: $servicePriceLabel',
                    style: _documentMetaStyle,
                  ),
                ],
              );
            },
          ),
          _divider(),
          Row(
            children: [
              Expanded(
                child: _DocActionButton(
                  icon: Icons.remove_red_eye,
                  label: 'View',
                  primary: true,
                  onTap: onView,
                  labelStyle: _actionLabelStyle,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _DocActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                  labelStyle: _actionLabelStyle,
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
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.28),
                    ),
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

List<PopupMenuEntry<String>> _bookingStatusMenuItems({
  required String current,
}) {
  final currentNormalized = current.trim().toUpperCase().replaceAll(' ', '_');
  const options = <String>[
    'MISSING',
    'ASSIGNED',
    'PENDING',
    'SCHEDULED',
    'READY',
    'ONGOING',
    'HANDLE_CLIENT',
    'COMPLETED',
    'CANCELLED',
  ];

  return options
      .map((status) {
        final isSelected = currentNormalized == status;
        final label = status.replaceAll('_', ' ');
        return PopupMenuItem<String>(
          value: status,
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (isSelected) const Icon(Icons.check_rounded, size: 18),
            ],
          ),
        );
      })
      .toList(growable: false);
}

class _BookingsAnalyticsCard extends StatelessWidget {
  const _BookingsAnalyticsCard({
    required this.mode,
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.monthBookingsStream,
    required this.monthPaymentsStream,
  });

  final _AdminBookingsMode mode;
  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Stream<QuerySnapshot<Map<String, dynamic>>> monthBookingsStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> monthPaymentsStream;

  static bool _isPaidPayment(Map<String, dynamic> data) {
    final raw = (data['paymentStatus'] ?? data['status'])?.toString() ?? '';
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
    if (normalized == '1' || normalized == 'PAID') return true;
    if (normalized.contains('SUCCESS')) return true;
    return false;
  }

  static bool _isCompletedBooking(Map<String, dynamic> data) {
    final raw = data['status']?.toString() ?? '';
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
    return normalized == 'COMPLETED' ||
        normalized == 'PAID' ||
        normalized == 'DONE';
  }

  static bool _isEmergencyAlertBooking(Map<String, dynamic> data) {
    final statusRaw = (data['status']?.toString() ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_');
    if (statusRaw == 'EMERGENCY_ALERT') return true;
    final serviceRaw =
        (data['service'] ?? data['type'] ?? data['title'])?.toString() ?? '';
    final service = serviceRaw.trim().toUpperCase().replaceAll(' ', '_');
    return service == 'EMERGENCY_ALERT';
  }

  @override
  Widget build(BuildContext context) {
    final stream = mode == _AdminBookingsMode.payments
        ? monthPaymentsStream
        : monthBookingsStream;

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
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox.shrink();

          final docs = snapshot.data?.docs ?? const [];
          var primaryCount = 0;
          var secondaryCount = 0;

          if (mode == _AdminBookingsMode.payments) {
            for (final d in docs) {
              final data = d.data();
              if (_isPaidPayment(data)) {
                primaryCount += 1;
              } else {
                secondaryCount += 1;
              }
            }
          } else {
            for (final d in docs) {
              final data = d.data();
              if (_isEmergencyAlertBooking(data)) continue;
              if (_isCompletedBooking(data)) {
                primaryCount += 1;
              } else {
                secondaryCount += 1;
              }
            }
          }

          final total = primaryCount + secondaryCount;
          final primaryLabel = mode == _AdminBookingsMode.payments
              ? 'Paid'
              : 'Completed';
          final secondaryLabel = mode == _AdminBookingsMode.payments
              ? 'Pending'
              : 'Active';

          final segments = <_DonutSegment>[
            _DonutSegment(
              label: secondaryLabel,
              count: secondaryCount,
              color: const Color(0xFFF4B63D),
            ),
            _DonutSegment(
              label: primaryLabel,
              count: primaryCount,
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
                          if (s.label == primaryLabel)
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
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: _profileDarkText,
          ),
        ),
      ],
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

    var startAngle = -math.pi / 2;
    for (final s in segments) {
      if (s.count <= 0) continue;
      final sweep = (s.count / total) * math.pi * 2;
      paint.color = s.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.segments != segments;
  }
}

class _PaymentDocCard extends StatelessWidget {
  const _PaymentDocCard({
    required this.indexNumber,
    required this.paymentId,
    required this.bookingId,
    required this.paymentMethod,
    required this.rawStatus,
  });

  final int indexNumber;
  final String paymentId;
  final String bookingId;
  final String paymentMethod;
  final String rawStatus;

  static String _statusLabel(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
    if (normalized.isEmpty) return 'UNKNOWN';
    if (normalized == '1') return 'PAID';
    if (normalized == '2') return 'PENDING';
    if (normalized == '3') return 'FAILED';
    return normalized;
  }

  static Color _statusDot(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized.contains('PAID') || normalized.contains('SUCCESS')) {
      return Colors.green.shade700;
    }
    if (normalized.contains('PENDING')) {
      return const Color(0xFFF4B63D);
    }
    if (normalized.contains('FAILED') || normalized.contains('CANCEL')) {
      return Colors.red.shade700;
    }
    return Colors.grey.shade600;
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiTokens.s12),
      child: Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: 0.85,
          child: Container(height: 1.2, color: Colors.black.withAlpha(20)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.shade300;
    final status = _statusLabel(rawStatus);
    final title = bookingId.trim().isNotEmpty ? bookingId.trim() : 'Payment';
    final fileLine = paymentMethod.trim().isNotEmpty
        ? paymentMethod.trim()
        : paymentId.trim();
    final metaLine = paymentId.trim().isNotEmpty
        ? 'Payment ID: $paymentId'
        : '-';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
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
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _primaryBlue.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      size: UiTokens.icon24,
                      color: _primaryBlue,
                    ),
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
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _profileDarkText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _DocTextChip(
                          label: status,
                          dotColor: _statusDot(status),
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: UiTokens.s4),
                    Text(
                      fileLine,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0x991B1D29),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: UiTokens.s2),
                    Text(
                      metaLine,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0x991B1D29),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          _divider(),
          Row(
            children: [
              Expanded(
                child: _DocActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy payment',
                  primary: true,
                  onTap: paymentId.trim().isNotEmpty
                      ? () => _copyValue(
                          context,
                          label: 'Payment ID',
                          value: paymentId,
                        )
                      : null,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
                  ),
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _DocActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy booking',
                  onTap: bookingId.trim().isNotEmpty
                      ? () => _copyValue(
                          context,
                          label: 'Booking ID',
                          value: bookingId,
                        )
                      : null,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _profileDarkText,
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

class _BookingDetailsSheet extends StatefulWidget {
  const _BookingDetailsSheet({required this.entry});

  final _BookingEntry entry;

  @override
  State<_BookingDetailsSheet> createState() => _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends State<_BookingDetailsSheet> {
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
                          'Booking details',
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
                  _AdminBookingDetailsTabs(entry: widget.entry),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminBookingDetailsTabs extends StatefulWidget {
  const _AdminBookingDetailsTabs({required this.entry});

  final _BookingEntry entry;

  @override
  State<_AdminBookingDetailsTabs> createState() =>
      _AdminBookingDetailsTabsState();
}

class _AdminBookingDetailsTabsState extends State<_AdminBookingDetailsTabs> {
  int _selectedTabIndex = 0;

  static const Color _cardBorder = Color(0xFFEBEDF0);
  static const Color _accentGreen = Color(0xFF00A8A7);
  static const Color _cardShadow = Color(0x1A0B0C10);
  static const Color _cardBorderStrong = Color(0xFFE1E4EA);
  static const double _cardRadius = 18;
  static const Color _mutedText = Color(0xFF6B7280);
  static const Color _avatarOutlineColor = Colors.white;

  static const TextStyle _sectionHeaderTextStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: _profileDarkText,
    letterSpacing: -0.15,
  );

  static const TextStyle _fieldLabelTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: _mutedText,
  );

  static const TextStyle _fieldValueTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: _profileDarkText,
    height: 1.25,
  );

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
  _resolvePersonDisplay(
    Map<String, dynamic> booking,
    Map<String, dynamic>? user,
  ) {
    final rawName =
        normalizeString(booking['personName']) ??
        normalizeString(user?['defaultPerson']) ??
        'Selected person';
    final rawLabel =
        normalizeString(booking['personLabel']) ?? 'Care recipient';
    final rawPhone =
        normalizeString(booking['personPhone']) ??
        normalizeString(booking['phone']) ??
        normalizeString(user?['phone']) ??
        '-';
    final addressText =
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['address']) ??
        normalizeString(user?['defaultAddress']) ??
        'Location not provided';
    final photoUrl =
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

  Future<({Map<String, dynamic>? user, Map<String, dynamic>? caregiver})>
  _loadRelated({required String userId, required String caregiverId}) async {
    Map<String, dynamic>? user;
    Map<String, dynamic>? caregiver;
    try {
      if (userId.trim().isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId.trim())
            .get();
        user = snap.data();
      }
    } catch (_) {}
    try {
      if (caregiverId.trim().isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('caregivers')
            .doc(caregiverId.trim())
            .get();
        caregiver = snap.data();
      }
    } catch (_) {}
    return (user: user, caregiver: caregiver);
  }

  Widget _buildBookingDetailsTab({
    required Map<String, dynamic> booking,
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? caregiver,
  }) {
    final date =
        (normalizeString(booking['date']) ??
                normalizeString(booking['scheduledDate']) ??
                '')
            .trim();
    final time = (normalizeString(booking['time']) ?? '').trim();
    final payment = normalizeString(booking['paymentMethod']) ?? 'Unknown';
    final notes =
        normalizeString(booking['personNotes'] ?? booking['notes']) ?? '';

    final personDisplay = _resolvePersonDisplay(booking, user);
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

    final ownerName =
        normalizeString(user?['name']) ??
        normalizeString(booking['userName']) ??
        'Client';
    final ownerPhone =
        normalizeString(user?['phone']) ??
        normalizeString(booking['userPhone']) ??
        'No contact';

    final caregiverName =
        normalizeString(caregiver?['name']) ??
        normalizeString(booking['caregiverName']) ??
        'Caregiver';
    final caregiverPhone =
        normalizeString(caregiver?['phone']) ??
        normalizeString(caregiver?['phoneNumber']) ??
        normalizeString(booking['caregiverPhone']) ??
        '-';
    final caregiverAddress =
        normalizeString(caregiver?['defaultAddress']) ??
        normalizeString(caregiver?['address']) ??
        normalizeString(caregiver?['area']) ??
        'Location not provided';
    final caregiverPhotoUrl =
        (normalizeString(caregiver?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(caregiver?['photoUrl'])!.trim()
        : (normalizeString(caregiver?['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(caregiver?['imageUrl'])!.trim()
              : null));
    final caregiverServices = extractServicePreferencesList(
      caregiver?['servicePreferences'] ?? caregiver?['services'],
    );
    final caregiverServiceFallback =
        normalizeString(caregiver?['service']) ?? '';
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
            value: date.isNotEmpty ? _formatDate(date) : '—',
          ),
          _buildInfoRow(
            icon: Icons.access_time,
            title: 'Time',
            value: time.isNotEmpty ? _formatTime(time) : '—',
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

  Widget _buildCaregiverDetailsTab({
    required Map<String, dynamic>? caregiver,
    required String caregiverId,
    required Map<String, dynamic> booking,
  }) {
    if (caregiver == null && caregiverId.trim().isEmpty) {
      return _buildUnavailablePlaceholder(
        message: 'Caregiver unavailable',
        explanation: 'This booking does not have a caregiver assigned.',
        centerVertically: true,
      );
    }

    final caregiverName =
        normalizeString(caregiver?['name']) ??
        normalizeString(booking['caregiverName']) ??
        'Caregiver';
    final caregiverPhotoUrl =
        (normalizeString(caregiver?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(caregiver?['photoUrl'])!.trim()
        : (normalizeString(caregiver?['imageUrl'])?.trim().isNotEmpty == true
              ? normalizeString(caregiver?['imageUrl'])!.trim()
              : null));
    final caregiverPhone =
        normalizeString(caregiver?['phone']) ??
        normalizeString(caregiver?['phoneNumber']) ??
        normalizeString(booking['caregiverPhone']) ??
        '—';
    final caregiverAddress =
        normalizeString(caregiver?['defaultAddress']) ??
        normalizeString(caregiver?['address']) ??
        normalizeString(caregiver?['area']) ??
        '—';
    final bioRaw = (caregiver?['bio'] as String?)?.trim() ?? '';
    final prefs = extractServicePreferencesList(
      caregiver?['servicePreferences'] ?? caregiver?['services'],
    );
    final fallbackServiceLabel = normalizeString(caregiver?['service']) ?? '';
    final servicesValue = prefs.isNotEmpty
        ? prefs.join(', ')
        : (fallbackServiceLabel.trim().isNotEmpty
              ? fallbackServiceLabel.trim()
              : 'Unavailable');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Caregiver details'),
        const SizedBox(height: 4),
        _centerAvatar(caregiverName, caregiverPhotoUrl),
        _buildTabContent([
          if (caregiverId.trim().isNotEmpty)
            _buildInfoRow(
              icon: Icons.badge_outlined,
              title: 'Caregiver ID',
              value: caregiverId.trim(),
            ),
          _buildInfoRow(
            icon: Icons.person,
            title: 'Caregiver name',
            value: caregiverName,
          ),
          _buildInfoRow(
            icon: Icons.medical_services_outlined,
            title: 'Services',
            value: servicesValue,
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
  }

  Widget _buildClientDetailsTab({
    required Map<String, dynamic> booking,
    required Map<String, dynamic>? user,
  }) {
    final ownerName =
        normalizeString(user?['name']) ??
        normalizeString(booking['userName']) ??
        'Client';
    final ownerPhone =
        normalizeString(user?['phone']) ??
        normalizeString(booking['userPhone']) ??
        '—';
    final personName =
        normalizeString(booking['personName']) ??
        normalizeString(user?['defaultPerson']) ??
        '—';
    final personLabel =
        normalizeString(booking['personLabel']) ?? 'Care recipient';
    final careLocation =
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['address']) ??
        normalizeString(user?['defaultAddress']) ??
        '—';
    final notes =
        normalizeString(booking['personNotes'] ?? booking['notes']) ?? '';

    return Column(
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
    );
  }

  Widget _buildEmergencyContactsTab({required Map<String, dynamic>? user}) {
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

  @override
  Widget build(BuildContext context) {
    const tabLabels = <String>[
      'Booking details',
      'Caregiver details',
      'Client details',
      'Emergency contact',
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
          stream: widget.entry.booking.reference.snapshots(),
          builder: (context, snapshot) {
            final booking = snapshot.data?.data() ?? widget.entry.rawData;
            final caregiverId =
                normalizeString(booking['caregiverId']) ??
                widget.entry.caregiverId;
            final userId =
                normalizeString(booking['userId']) ??
                normalizeString(booking['ownerUserId']) ??
                widget.entry.userId;

            return FutureBuilder<
              ({Map<String, dynamic>? user, Map<String, dynamic>? caregiver})
            >(
              future: _loadRelated(userId: userId, caregiverId: caregiverId),
              builder: (context, relatedSnap) {
                final user = relatedSnap.data?.user;
                final caregiver = relatedSnap.data?.caregiver;

                Widget content;
                if (_selectedTabIndex == 0) {
                  content = _buildBookingDetailsTab(
                    booking: booking,
                    user: user,
                    caregiver: caregiver,
                  );
                } else if (_selectedTabIndex == 1) {
                  content = _buildCaregiverDetailsTab(
                    caregiver: caregiver,
                    caregiverId: caregiverId,
                    booking: booking,
                  );
                } else if (_selectedTabIndex == 2) {
                  content = _buildClientDetailsTab(
                    booking: booking,
                    user: user,
                  );
                } else {
                  content = _buildEmergencyContactsTab(user: user);
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

class _AdminBookingEditSheet extends StatefulWidget {
  const _AdminBookingEditSheet({required this.booking});

  final DocumentSnapshot<Map<String, dynamic>> booking;

  @override
  State<_AdminBookingEditSheet> createState() => _AdminBookingEditSheetState();
}

class _AdminBookingEditSheetState extends State<_AdminBookingEditSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _serviceCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _paymentMethodCtrl;
  late final TextEditingController _notesCtrl;
  final TextEditingController _bookingIdCtrl = TextEditingController();
  final LayerLink _serviceFieldLink = LayerLink();
  final GlobalKey _serviceFieldKey = GlobalKey();
  OverlayEntry? _serviceOverlayEntry;
  var _serviceOptions = const <_ServiceOption>[];
  var _servicesLoading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.booking.data() ?? const <String, dynamic>{};
    _bookingIdCtrl.text = widget.booking.id;
    _serviceCtrl = TextEditingController(
      text: (data['service'] as String?) ?? (data['title'] as String?) ?? '',
    );
    _dateCtrl = TextEditingController(
      text:
          (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '',
    );
    _timeCtrl = TextEditingController(text: (data['time'] as String?) ?? '');
    _paymentMethodCtrl = TextEditingController(
      text: (data['paymentMethod'] as String?) ?? '',
    );
    _notesCtrl = TextEditingController(
      text:
          (data['personNotes'] as String?) ?? (data['notes'] as String?) ?? '',
    );
    _loadServiceCatalog();
  }

  @override
  void dispose() {
    _closeServiceMenu();
    _serviceCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _paymentMethodCtrl.dispose();
    _notesCtrl.dispose();
    _bookingIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServiceCatalog() async {
    if (_servicesLoading) return;
    setState(() => _servicesLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('services')
          .orderBy('name')
          .get();
      final next = <_ServiceOption>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        next.add(_ServiceOption(label: name, value: name));
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

  void _selectService(_ServiceOption option) {
    setState(() {
      _serviceCtrl.text = option.value;
    });
    _closeServiceMenu();
  }

  Future<void> _pickDate() async {
    DateTime initialDate = DateTime.now();
    final raw = _dateCtrl.text.trim();
    if (raw.isNotEmpty) {
      try {
        initialDate = DateTime.parse(raw);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: availabilityPickerBuilder,
    );
    if (picked == null) return;
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {});
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    final raw = _timeCtrl.text.trim();
    if (raw.isNotEmpty) {
      final match = RegExp(r'^(\\d{1,2}):(\\d{2})$').firstMatch(raw);
      if (match != null) {
        final h = int.tryParse(match.group(1)!);
        final m = int.tryParse(match.group(2)!);
        if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          initial = TimeOfDay(hour: h, minute: m);
        }
      }
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: availabilityPickerBuilder,
    );
    if (picked == null) return;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    _timeCtrl.text = '$h:$m';
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.booking.reference.set({
        'service': _serviceCtrl.text.trim(),
        'date': _dateCtrl.text.trim(),
        'scheduledDate': _dateCtrl.text.trim(),
        'time': _timeCtrl.text.trim(),
        'paymentMethod': _paymentMethodCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'personNotes': _notesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update booking. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final data = widget.booking.data() ?? const <String, dynamic>{};
    final caregiverId = ((data['caregiverId'] as String?) ?? '').trim();
    final caregiverRef = caregiverId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(caregiverId);

    InputDecoration inputDecoration({
      required String labelText,
      Widget? suffixIcon,
      bool alignLabelWithHint = false,
      bool floatingLabelAlways = false,
      String? hintText,
    }) {
      return InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.55),
        ),
        alignLabelWithHint: alignLabelWithHint,
        floatingLabelBehavior:
            floatingLabelAlways ? FloatingLabelBehavior.always : null,
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _profileDarkText,
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
                          'Edit booking',
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
                    controller: _bookingIdCtrl,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: inputDecoration(labelText: 'Booking ID'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Booking details',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: _profileDarkText,
                    ),
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
                      decoration: inputDecoration(
                        labelText: 'Services',
                        suffixIcon: const Icon(Icons.expand_more, size: 18),
                      ),
                      onTap: _toggleServiceMenu,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Please enter services.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                      child: TextFormField(
                          controller: _dateCtrl,
                          readOnly: true,
                          showCursor: false,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _profileDarkText,
                          ),
                          decoration: inputDecoration(
                            labelText: 'Booked date',
                            floatingLabelAlways: true,
                            hintText: 'Select date',
                          ),
                          onTap: _saving ? null : _pickDate,
                        ),
                      ),
                      const SizedBox(width: UiTokens.s8),
                      Expanded(
                        child: TextFormField(
                          controller: _timeCtrl,
                          readOnly: true,
                          showCursor: false,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _profileDarkText,
                          ),
                          decoration: inputDecoration(
                            labelText: 'Booked time',
                            floatingLabelAlways: true,
                            hintText: 'Select time',
                          ),
                          onTap: _saving ? null : _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _paymentMethodCtrl,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: inputDecoration(labelText: 'Payment method'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesCtrl,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: inputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                      floatingLabelAlways: true,
                      hintText: 'Enter notes',
                    ),
                    minLines: 1,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactStatusChip extends StatelessWidget {
  const _CompactStatusChip({
    required this.label,
    required this.dotColor,
    this.maxLabelWidth,
  });

  final String label;
  final Color dotColor;
  final double? maxLabelWidth;

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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxLabelWidth ?? double.infinity,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 7.5,
                color: Colors.black.withValues(alpha: 0.80),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTextChip extends StatelessWidget {
  const _DocTextChip({
    required this.label,
    required this.dotColor,
    required this.textStyle,
  });

  final String label;
  final Color dotColor;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UiTokens.s8,
        vertical: UiTokens.s4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

class _DocActionButton extends StatelessWidget {
  const _DocActionButton({
    required this.icon,
    required this.label,
    required this.labelStyle,
    this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final TextStyle labelStyle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final backgroundColor = primary
        ? (isEnabled ? _tealAccent : Colors.grey.shade400)
        : Colors.white;
    final borderColor = primary ? _tealAccent : Colors.grey.shade300;
    final foreground = primary
        ? Colors.white
        : _profileDarkText.withValues(alpha: isEnabled ? 1 : 0.35);
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
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
            Text(label, style: labelStyle.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

class _ServiceOption {
  const _ServiceOption({required this.label, required this.value});

  final String label;
  final String value;
}

Future<void> _copyValue(
  BuildContext context, {
  required String label,
  required String value,
}) async {
  final v = value.trim();
  if (v.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: v));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label copied')));
}
