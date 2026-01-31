import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/schedule_booking_telegram_sheet.dart';

import 'booking_person_screen.dart';
import '../user_root_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_addresses_screen.dart';
import '../../../constants/service_options.dart';
import '../../../models/caregiver_model.dart';

const Color _tealAccent = Color(0xFF00A8A7);
const Color _actionGold = Color(0xFFF4B63D);
const Color _bookingAppBarText = Color(0xFF1B1D29);
const Color _pageBackground = Color(0xFFF7F8FA);
const TextStyle _sectionLabelTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: Color(0xFF1B1D29),
);
final _weekdayFormatter = intl.DateFormat('EEE');
final _dayFormatter = intl.DateFormat('d');

class _SlowScrollPhysics extends BouncingScrollPhysics {
  const _SlowScrollPhysics({super.parent, required this.speedFactor})
    : assert(speedFactor > 0);

  final double speedFactor;

  @override
  _SlowScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SlowScrollPhysics(
      parent: buildParent(ancestor),
      speedFactor: speedFactor,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset) * speedFactor;
  }
}

class _WeeklyTimeRange {
  const _WeeklyTimeRange({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class BookingSummaryScreen extends StatefulWidget {
  const BookingSummaryScreen({
    super.key,
    required this.person,
    required this.caregiver,
    required this.scheduleDate,
    required this.startTime,
    required this.endTime,
    required this.price,
    required this.selectedAddress,
    required this.showScheduleSection,
    this.distanceKm,
    this.editingBookingId,
    this.lockedService,
    this.lockedPaymentMethod,
    this.readOnlyServiceAndPayment = false,
    this.enableClientAddressSelection = false,
  });

  final PersonProfile person;
  final CaregiverModel caregiver;
  final DateTime scheduleDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double price;
  final AddressItem selectedAddress;
  final bool showScheduleSection;
  final double? distanceKm;
  final String? editingBookingId;
  final String? lockedService;
  final String? lockedPaymentMethod;
  final bool readOnlyServiceAndPayment;
  final bool enableClientAddressSelection;

  @override
  State<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends State<BookingSummaryScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  String _selectedService = '';
  Map<String, Map<String, dynamic>> _serviceCatalogByName = const {};
  bool _serviceCatalogLoading = false;
  final TextEditingController _bookingNotesController = TextEditingController();
  double? _distanceKmOverride;
  double? _distanceChargeOverride;
  static const bool _forceToyyibTestAmount = false;
  static const int _minMinutesBetweenStartEnd = 15;
  TimeOfDay? _bookInAdvanceStartOverride;
  TimeOfDay? _bookInAdvanceEndOverride;
  StateSetter? _scheduleBookingSheetSetState;
  late DateTime _selectedDate;
  late DateTime _scheduleAnchorDate;
  late List<TimeOfDay> _timeOptions;
  late int _selectedTimeIndex;
  late bool _isBookInAdvance;
  late final int _scheduledDurationMinutes;
  bool _showPaymentMethods = false;
  bool _showServicePreferences = false;
  String? _selectedPaymentMethod;
  String? _pendingPaymentBillCode;
  bool _awaitingPaymentResult = false;
  bool _paymentFailureDialogShown = false;
  bool _paymentSuccessDialogShown = false;
  bool _modalSheetScrimVisible = false;
  late PersonProfile _currentPerson;
  late AddressItem _activeAddress;
  static const double _scheduleChipWidth = 52;
  static const double _scheduleChipSpacing = 58;
  final ScrollController _scheduleScrollController = ScrollController();
  double _scheduleViewportWidth = 0;
  double _scheduleSidePadding = 0;
  double _scheduleMinOffset = 0;
  bool _scheduleScrollAnimating = false;
  bool _scheduleAutoCentered = false;
  String? _scheduleCenterKey;
  Timer? _scheduleSnapDebounce;
  List<DateTime> _scheduleLayoutDaysSnapshot = const <DateTime>[];
  List<DateTimeRange> _scheduleRangesSnapshot = const <DateTimeRange>[];
  Set<int> _scheduleDisabledWeekdaysSnapshot = const <int>{};
  int? _scheduleLastSnappedIndex;
  static const _SlowScrollPhysics _scheduleScrollPhysics = _SlowScrollPhysics(
    speedFactor: 0.7,
  );

  static const double _timeChipWidth = 60;
  static const double _timeChipSpacing = 68;
  final ScrollController _timeScrollController = ScrollController();
  double _timeViewportWidth = 0;
  double _timeSidePadding = 0;
  double _timeMinOffset = 0;
  bool _timeScrollAnimating = false;
  bool _timeAutoCentered = false;
  String? _timeCenterKey;
  Timer? _timeSnapDebounce;
  Map<int, _WeeklyTimeRange> _weeklyTimeRanges = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPerson = widget.person;
    _activeAddress = widget.selectedAddress;
    _scheduledDurationMinutes = _durationMinutes(
      widget.startTime,
      widget.endTime,
    );
    final now = DateTime.now();
    _selectedDate = widget.showScheduleSection
        ? _clampToFuture(widget.scheduleDate)
        : now;
    _scheduleAnchorDate = _normalizeDate(_selectedDate);
    final baseOptions = List.generate(11, (index) {
      final hour = 8 + index;
      return TimeOfDay(hour: hour, minute: 0);
    });
    final wantedStart = widget.showScheduleSection
        ? widget.startTime
        : TimeOfDay.fromDateTime(now);
    final matchingIndex = baseOptions.indexWhere(
      (t) => t.hour == wantedStart.hour && t.minute == wantedStart.minute,
    );
    if (matchingIndex >= 0) {
      _timeOptions = baseOptions;
      _selectedTimeIndex = matchingIndex;
    } else {
      _timeOptions = [...baseOptions, wantedStart];
      _selectedTimeIndex = _timeOptions.length - 1;
    }
    _isBookInAdvance = widget.showScheduleSection;
    if (_isBookInAdvance) {
      _timeOptions = const <TimeOfDay>[];
      _selectedTimeIndex = 0;
    }
    if (widget.lockedService?.isNotEmpty == true) {
      _selectedService = widget.lockedService!;
    }
    _selectedPaymentMethod = widget.lockedPaymentMethod;
    _loadServiceCatalog();
    _loadBookingMetadataForEdit();
  }

  Future<void> _loadBookingMetadataForEdit() async {
    final bookingId = widget.editingBookingId?.trim() ?? '';
    if (bookingId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();
      final data = snap.data();
      if (!mounted || data == null) return;
      final notes = (data['bookingNotes'] as String?)?.trim() ?? '';
      final distanceKm = _coerceToDouble(data['distanceKm']);
      final distanceCharge = _coerceToDouble(data['distanceCharge']);
      setState(() {
        _bookingNotesController.text = notes;
        _distanceKmOverride = distanceKm;
        _distanceChargeOverride = distanceCharge;
      });
    } catch (_) {
      // Ignore; edit screen remains usable.
    }
  }

  Future<void> _loadServiceCatalog() async {
    if (_serviceCatalogLoading) return;
    setState(() => _serviceCatalogLoading = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('services').get();
      final next = <String, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        next[name] = data;
      }
      if (!mounted) return;
      setState(() => _serviceCatalogByName = next);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _serviceCatalogLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPaymentStatus();
    }
  }

  Future<void> _checkPendingPaymentStatus() async {
    if (!_awaitingPaymentResult) return;
    final billCode = _pendingPaymentBillCode;
    if (billCode == null || billCode.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .doc(billCode)
          .get();
      final data = snap.data();
      final rawStatus = data?['status'];
      final paymentStatus = (data?['paymentStatus'] as String?)
          ?.trim()
          .toUpperCase();
      final int? statusValue = rawStatus is num ? rawStatus.toInt() : null;

      final bool isPaid = statusValue == 1 || paymentStatus == 'PAID';
      final bool isCancelled =
          paymentStatus == 'CANCELLED' || paymentStatus == 'CANCELED';
      final bool isFailed =
          statusValue == 3 || paymentStatus == 'FAILED' || isCancelled;

      if (isPaid) {
        if (!mounted) return;
        setState(() {
          _awaitingPaymentResult = false;
          _pendingPaymentBillCode = null;
          _paymentFailureDialogShown = false;
          _paymentSuccessDialogShown = true;
        });
        await _showPaymentResultDialog(
          title: 'Payment successful',
          message: 'Your booking has been placed successfully.',
        );
        return;
      }

      if (isFailed && !_paymentFailureDialogShown) {
        if (!mounted) return;
        setState(() {
          _paymentFailureDialogShown = true;
          _awaitingPaymentResult = false;
          _pendingPaymentBillCode = null;
        });
        await _showPaymentErrorDialog(
          isCancelled
              ? 'Payment was cancelled. Please try again.'
              : 'Payment failed. Please try again.',
        );
      }
    } catch (_) {
      // ignore payment status polling errors on resume
    }
  }

  int _nearestScheduleIndex({
    required List<DateTime> layoutDays,
    required double center,
  }) {
    final exactIndex =
        (center - _scheduleSidePadding - (_scheduleChipWidth / 2)) /
        _scheduleChipSpacing;
    final baseIndex = exactIndex.floor();
    int nearestIndex = baseIndex.clamp(0, layoutDays.length - 1);
    double bestDistance = double.infinity;
    for (int i = baseIndex - 8; i <= baseIndex + 8; i++) {
      if (i < 0 || i >= layoutDays.length) continue;
      final itemCenter =
          _scheduleSidePadding +
          (i * _scheduleChipSpacing) +
          (_scheduleChipWidth / 2);
      final distance = (itemCenter - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  int _nearestTimeIndex({required int itemCount, required double center}) {
    final exactIndex =
        (center - _timeSidePadding - (_timeChipWidth / 2)) / _timeChipSpacing;
    final baseIndex = exactIndex.floor();
    int nearestIndex = baseIndex.clamp(0, itemCount - 1);
    double bestDistance = double.infinity;
    for (int i = baseIndex - 8; i <= baseIndex + 8; i++) {
      if (i < 0 || i >= itemCount) continue;
      final itemCenter =
          _timeSidePadding + (i * _timeChipSpacing) + (_timeChipWidth / 2);
      final distance = (itemCenter - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  TimeOfDay get _selectedStartTimeValue {
    if (_isBookInAdvance && _bookInAdvanceStartOverride != null) {
      return _bookInAdvanceStartOverride!;
    }
    if (_timeOptions.isNotEmpty &&
        _selectedTimeIndex >= 0 &&
        _selectedTimeIndex < _timeOptions.length) {
      return _timeOptions[_selectedTimeIndex];
    }
    return widget.startTime;
  }

  TimeOfDay get _selectedEndTimeValue {
    final start = _selectedStartTimeValue;
    if (_isBookInAdvance && _bookInAdvanceEndOverride != null) {
      return _bookInAdvanceEndOverride!;
    }
    if (!_isBookInAdvance) return widget.endTime;

    final range = _weeklyTimeRanges[_selectedDate.weekday];
    final startMin = _toMinutes(start);
    final minEndMin = startMin + _minMinutesBetweenStartEnd;
    int endMin = startMin + _scheduledDurationMinutes;

    if (range != null) {
      final maxMin = _toMinutes(range.end);
      if (endMin > maxMin) endMin = maxMin;
      if (endMin < minEndMin) endMin = minEndMin.clamp(0, maxMin);
    } else {
      if (endMin < minEndMin) endMin = minEndMin;
      endMin = endMin.clamp(0, 24 * 60 - 1);
    }

    return _fromMinutes(endMin);
  }

  int _toMinutes(TimeOfDay t) => (t.hour * 60) + t.minute;

  TimeOfDay _fromMinutes(int minutes) {
    final clamped = minutes.clamp(0, 24 * 60 - 1);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  int _durationMinutes(TimeOfDay start, TimeOfDay end) {
    final diff = _toMinutes(end) - _toMinutes(start);
    if (diff >= _minMinutesBetweenStartEnd) return diff;
    // Fallback for invalid/negative durations (shouldn't happen normally).
    return 120;
  }

  void _syncTimeOptionsForDate(DateTime date) {
    if (!_isBookInAdvance) return;
    final next = _buildTimeOptionsForDate(date, _weeklyTimeRanges);
    if (next.isEmpty) {
      if (_timeOptions.isNotEmpty) {
        _setStateAndRefreshScheduleSheet(() {
          _timeOptions = const <TimeOfDay>[];
          _selectedTimeIndex = 0;
          _timeAutoCentered = false;
        });
      }
      return;
    }

    final currentSelected = _timeOptions.isNotEmpty
        ? _selectedStartTimeValue
        : null;
    int newIndex = currentSelected == null
        ? -1
        : next.indexWhere(
            (t) =>
                t.hour == currentSelected.hour &&
                t.minute == currentSelected.minute,
          );
    if (newIndex < 0) {
      final wantedStart = widget.startTime;
      newIndex = next.indexWhere(
        (t) => t.hour == wantedStart.hour && t.minute == wantedStart.minute,
      );
    }
    if (newIndex < 0) newIndex = 0;

    final firstAllowedIndex = next.indexWhere((t) => !_isTimeDisabled(t));
    if (firstAllowedIndex >= 0 && newIndex < firstAllowedIndex) {
      newIndex = firstAllowedIndex;
    }

    final sameList =
        _timeOptions.length == next.length &&
        _timeOptions.asMap().entries.every((e) {
          final t = next[e.key];
          return t.hour == e.value.hour && t.minute == e.value.minute;
        });
    if (sameList && _selectedTimeIndex == newIndex) return;

    _setStateAndRefreshScheduleSheet(() {
      _timeOptions = next;
      _selectedTimeIndex = newIndex.clamp(0, _timeOptions.length - 1);
      _timeAutoCentered = false;
    });
  }

  List<TimeOfDay> _buildTimeOptionsForDate(
    DateTime date,
    Map<int, _WeeklyTimeRange> ranges,
  ) {
    final range = ranges[date.weekday];
    if (range == null) return const <TimeOfDay>[];
    return _generateTimeSlots(
      start: range.start,
      end: range.end,
      minuteInterval: 15,
    );
  }

  void _updateWeeklyTimeRanges(Map<int, _WeeklyTimeRange> next) {
    bool equals(Map<int, _WeeklyTimeRange> a, Map<int, _WeeklyTimeRange> b) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        final other = b[entry.key];
        if (other == null) return false;
        if (other.start.hour != entry.value.start.hour ||
            other.start.minute != entry.value.start.minute ||
            other.end.hour != entry.value.end.hour ||
            other.end.minute != entry.value.end.minute) {
          return false;
        }
      }
      return true;
    }

    if (equals(_weeklyTimeRanges, next)) return;
    _setStateAndRefreshScheduleSheet(
      () => _weeklyTimeRanges = Map<int, _WeeklyTimeRange>.from(next),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTimeOptionsForDate(_selectedDate);
    });
  }

  void _handleScheduleScrollEnd(
    List<DateTimeRange> ranges,
    Set<int> disabledWeekdays,
    List<DateTime> layoutDays,
  ) {
    if (_scheduleScrollAnimating ||
        !_scheduleScrollController.hasClients ||
        layoutDays.isEmpty) {
      return;
    }
    final viewport = _scheduleScrollController.position.viewportDimension;
    if (viewport <= 0) return;
    final center = _scheduleScrollController.offset + (viewport / 2);
    int candidateIndex = _nearestScheduleIndex(
      layoutDays: layoutDays,
      center: center,
    );
    final firstAllowedIndex = layoutDays.indexWhere((d) => !_isPastDate(d));
    if (firstAllowedIndex >= 0 && candidateIndex < firstAllowedIndex) {
      candidateIndex = firstAllowedIndex;
    }
    final candidateDate = layoutDays[candidateIndex];
    if (!_isSameDay(candidateDate, _selectedDate)) {
      _setStateAndRefreshScheduleSheet(() => _selectedDate = candidateDate);
      _syncTimeOptionsForDate(candidateDate);
    }
    _scheduleLastSnappedIndex = candidateIndex;
    _scrollToDateIndex(candidateIndex);
  }

  void _handleTimeScrollEnd() {
    if (_timeScrollAnimating ||
        !_timeScrollController.hasClients ||
        _timeOptions.isEmpty) {
      return;
    }
    final viewport = _timeScrollController.position.viewportDimension;
    if (viewport <= 0) return;

    final center = _timeScrollController.offset + (viewport / 2);
    int candidateIndex = _nearestTimeIndex(
      itemCount: _timeOptions.length,
      center: center,
    );

    final firstAllowedIndex = _timeOptions.indexWhere(
      (t) => !_isTimeDisabled(t),
    );
    if (firstAllowedIndex >= 0 && candidateIndex < firstAllowedIndex) {
      candidateIndex = firstAllowedIndex;
    }

    if (candidateIndex != _selectedTimeIndex) {
      _setStateAndRefreshScheduleSheet(
        () => _selectedTimeIndex = candidateIndex,
      );
    }
    _scrollToTimeIndex(candidateIndex);
  }

  void _scrollToSelectedDateIndex({
    required List<DateTime> layoutDays,
    required List<DateTimeRange> ranges,
    required Set<int> disabledWeekdays,
    bool animate = false,
  }) {
    final index = layoutDays.indexWhere((d) => _isSameDay(d, _selectedDate));
    if (index >= 0) return _scrollToDateIndex(index, animate: animate);

    int? fallbackIndex;
    int bestDelta = 1 << 30;
    for (int i = 0; i < layoutDays.length; i++) {
      final day = layoutDays[i];
      if (_isDateDisabled(day, ranges, disabledWeekdays)) continue;
      final delta = (day.difference(_selectedDate).inDays).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        fallbackIndex = i;
      }
    }
    if (fallbackIndex == null) return;
    final fallbackDate = layoutDays[fallbackIndex];
    if (_isSameDay(fallbackDate, _selectedDate)) {
      return _scrollToDateIndex(fallbackIndex, animate: animate);
    }
    _setStateAndRefreshScheduleSheet(() => _selectedDate = fallbackDate);
    _syncTimeOptionsForDate(fallbackDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDateIndex(fallbackIndex!, animate: animate);
    });
  }

  void _setStateAndRefreshScheduleSheet(VoidCallback fn) {
    setState(fn);
    _scheduleBookingSheetSetState?.call(() {});
  }

  void _scrollToSelectedTimeIndex({bool animate = false}) {
    if (_selectedTimeIndex < 0 || _selectedTimeIndex >= _timeOptions.length) {
      return;
    }
    _scrollToTimeIndex(_selectedTimeIndex, animate: animate);
  }

  void _scrollToDateIndex(int index, {bool animate = true}) {
    if (!_scheduleScrollController.hasClients) {
      return;
    }
    final viewport = _scheduleScrollController.position.viewportDimension;
    if (viewport <= 0) return;
    final targetCenter =
        index * _scheduleChipSpacing +
        _scheduleSidePadding +
        (_scheduleChipWidth / 2);
    final desired = targetCenter - (viewport / 2);
    final maxExtent = _scheduleScrollController.position.maxScrollExtent;
    final target = desired.clamp(0.0, maxExtent);
    _scheduleScrollAnimating = true;
    if (animate) {
      _scheduleScrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _scheduleScrollAnimating = false);
    } else {
      _scheduleScrollController.jumpTo(target);
      _scheduleScrollAnimating = false;
    }
  }

  void _scrollToTimeIndex(int index, {bool animate = true}) {
    if (!_timeScrollController.hasClients) return;
    final viewport = _timeScrollController.position.viewportDimension;
    if (viewport <= 0) return;
    final targetCenter =
        index * _timeChipSpacing + _timeSidePadding + (_timeChipWidth / 2);
    final desired = targetCenter - (viewport / 2);
    final maxExtent = _timeScrollController.position.maxScrollExtent;
    final target = desired.clamp(_timeMinOffset, maxExtent);
    _timeScrollAnimating = true;
    if (animate) {
      _timeScrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _timeScrollAnimating = false);
    } else {
      _timeScrollController.jumpTo(target);
      _timeScrollAnimating = false;
    }
  }

  bool _isDateDisabled(
    DateTime date,
    List<DateTimeRange> ranges,
    Set<int> disabledWeekdays,
  ) {
    return _isPastDate(date) ||
        _isDateBlocked(date, ranges) ||
        disabledWeekdays.contains(date.weekday);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleSnapDebounce?.cancel();
    _timeSnapDebounce?.cancel();
    _scheduleScrollController.dispose();
    _timeScrollController.dispose();
    _bookingNotesController.dispose();
    super.dispose();
  }

  bool get _isEditingBooking => widget.editingBookingId != null;

  bool get _lockServiceAndPayment => widget.readOnlyServiceAndPayment;

  bool get _canUseAddressPicker => widget.enableClientAddressSelection;

  bool get _hasSelectedService {
    final lockedValue = widget.lockedService?.trim() ?? '';
    if (_lockServiceAndPayment && lockedValue.isNotEmpty) return true;
    return _selectedService.trim().isNotEmpty;
  }

  bool get _hasSelectedPaymentMethod => _selectedPaymentMethod != null;

  double _selectedServicePriceValue() {
    final selectedName = _selectedService.trim().isEmpty
        ? (widget.lockedService?.trim() ?? '')
        : _selectedService.trim();
    final details = _serviceCatalogByName[selectedName];
    final catalogPrice = _coerceToDouble(details?['price']);
    if (catalogPrice != null && catalogPrice > 0) return catalogPrice;
    return 0;
  }

  String? _selectedServicePerLabel() {
    final selectedName = _selectedService.trim().isEmpty
        ? (widget.lockedService?.trim() ?? '')
        : _selectedService.trim();
    final details = _serviceCatalogByName[selectedName];
    final per = (details?['per'] as String?)?.trim();
    return (per == null || per.isEmpty) ? null : per;
  }

  bool get _canConfirmBooking {
    if (_isEditingBooking) return !_isLoading;
    final servicePrice = _selectedServicePriceValue();
    return !_isLoading &&
        !_serviceCatalogLoading &&
        _hasSelectedService &&
        _hasSelectedPaymentMethod &&
        servicePrice > 0;
  }

  double _distanceKmValue() {
    return _distanceKmOverride ??
        widget.distanceKm ??
        widget.selectedAddress.distanceKm ??
        0.0;
  }

  double _distanceChargeValue() {
    return _distanceChargeOverride ?? widget.price;
  }

  Future<void> _confirmBooking() async {
    if (_isLoading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to place booking')),
      );
      return;
    }

    if (!_hasSelectedService) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_serviceCatalogLoading || _selectedServicePriceValue() <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service price is not available yet. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a payment method'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final serviceLabel = _selectedService.trim().isNotEmpty
          ? _selectedService.trim()
          : (widget.lockedService?.trim() ?? '');
      final pickupDetails = _currentPerson.notes.trim();
      final startTimeValue = _selectedStartTimeValue;
      final endTimeValue = _selectedEndTimeValue;
      final personAddress =
          (_activeAddress.addressLine ?? _activeAddress.subtitle).trim();
      final selectedServicePrice = _selectedServicePriceValue();
      final distanceKm = _distanceKmValue();
      final distanceCharge = _distanceChargeValue();
      final totalAmount = (selectedServicePrice + distanceCharge)
          .clamp(0.0, 999999.0)
          .toDouble();
      final billingAmount = _forceToyyibTestAmount ? 2.0 : totalAmount;
      final formattedDate = _formatDate(_selectedDate);
      final formattedTime = _formatTimeOfDay(startTimeValue);
      final formattedEndTime = _formatTimeOfDay(endTimeValue);
      final billName = _sanitizeToyyibText(
        'Booking $serviceLabel',
        maxLength: 30,
      );
      final billDescription = _sanitizeToyyibText(
        _isBookInAdvance
            ? 'Care booking for $serviceLabel on ${intl.DateFormat('EEE, d MMM yyyy').format(_selectedDate)} from $formattedTime to $formattedEndTime'
            : 'Care booking for $serviceLabel on ${intl.DateFormat('EEE, d MMM yyyy').format(_selectedDate)} at $formattedTime',
        maxLength: 200,
      );

      final bookingInfo = <String, dynamic>{
        'caregiverId': widget.caregiver.id,
        'caregiverName': widget.caregiver.name,
        'caregiverPhoto': widget.caregiver.photoUrl,
        'servicePreferences': [serviceLabel],
        'personId': _currentPerson.id,
        'personName': _currentPerson.name,
        'personAddress': personAddress,
        'addressId': _activeAddress.id,
        'addressLabel': _activeAddress.label ?? _currentPerson.label ?? '',
        'date': formattedDate,
        'paymentMethod': _selectedPaymentMethod!,
        'servicePrice': selectedServicePrice,
        'distanceKm': distanceKm,
        'distanceCharge': distanceCharge,
        'bookingNotes': _bookingNotesController.text.trim(),
        'personNotes': pickupDetails,
      };
      if (_isBookInAdvance) {
        bookingInfo['startTime'] = formattedTime;
        bookingInfo['endTime'] = formattedEndTime;
      } else {
        bookingInfo['time'] = formattedTime;
      }
      final checkout = await _createToyyibPayBill(
        serviceLabel: serviceLabel,
        billingAmount: billingAmount,
        bookingInfo: bookingInfo,
        billName: billName,
        billDescription: billDescription,
      );
      if (checkout == null) return;
      if (!mounted) return;
      setState(() {
        _awaitingPaymentResult = true;
        _pendingPaymentBillCode = checkout.billCode;
        _paymentFailureDialogShown = false;
        _paymentSuccessDialogShown = false;
      });
      await launchUrl(
        checkout.paymentUrl,
        mode: LaunchMode.externalApplication,
      );
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking unsuccessful. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBookingChanges() async {
    if (_isLoading || widget.editingBookingId == null) return;
    setState(() => _isLoading = true);
    try {
      final navigator = Navigator.of(context);
      final startTimeValue = _selectedStartTimeValue;
      final endTimeValue = _selectedEndTimeValue;
      final addressText =
          (_activeAddress.addressLine ?? _activeAddress.subtitle).trim();
      final updates = {
        'date': _formatDate(_selectedDate),
        'personName': _currentPerson.name,
        'personAddress': addressText,
        'personId': _currentPerson.id,
        'personPhone': _currentPerson.phone,
        'addressLabel': _activeAddress.label ?? _currentPerson.label ?? '',
        'caregiverName': widget.caregiver.name,
        'addressId': _activeAddress.id,
        'bookingNotes': _bookingNotesController.text.trim(),
        'distanceKm': _distanceKmValue(),
        'distanceCharge': _distanceChargeValue(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_isBookInAdvance) {
        updates['startTime'] = _formatTimeOfDay(startTimeValue);
        updates['endTime'] = _formatTimeOfDay(endTimeValue);
        updates['time'] = FieldValue.delete();
      } else {
        updates['time'] = _formatTimeOfDay(startTimeValue);
        updates['startTime'] = FieldValue.delete();
        updates['endTime'] = FieldValue.delete();
      }
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.editingBookingId)
          .update(updates);
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static const int _scheduleDaysBefore = 15;
  static const int _scheduleDaysAfter = 90;

  List<DateTime> get _scheduleDays {
    final anchor = _scheduleAnchorDate;
    return List.generate(
      _scheduleDaysBefore + _scheduleDaysAfter + 1,
      (index) => anchor.add(Duration(days: index - _scheduleDaysBefore)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: _pageBackground,
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
            color: _bookingAppBarText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Booking',
          style: TextStyle(
            color: _bookingAppBarText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('caregivers')
                .doc(widget.caregiver.id)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() ?? {};
              final location = _buildLocation(data);
              final defaultAddress =
                  (data['defaultAddress'] as String?)?.trim() ?? '';
              final serviceOptions = _safeStringList(
                data['servicePreferences'],
              ).where((s) => s.trim().isNotEmpty).toList();
              final services = serviceOptions.isNotEmpty
                  ? serviceOptions
                  : widget.caregiver.services;
              return Padding(
                padding: const EdgeInsets.only(bottom: 90),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildSectionTitle('Selected Caregiver & Client'),
                    ),
                    _buildProfileHeader(
                      location: location,
                      defaultAddress: defaultAddress,
                    ),
                    const SizedBox(height: 6),
                    _buildPersonCard(),
                    const SizedBox(height: 16),
                    if (_isBookInAdvance) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildSectionTitle('Schedule Booking Time'),
                      ),
                      const SizedBox(height: 6),
                      _buildScheduleBookingTimeCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildSectionTitle('Service Preferences'),
                    const SizedBox(height: 6),
                    _buildAddServiceCard(),
                    if (_showServicePreferences && !_lockServiceAndPayment) ...[
                      const SizedBox(height: 6),
                      ...services.map(
                        (service) => _buildServiceRow(service: service),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildSectionTitle('Booking Notes'),
                    const SizedBox(height: 6),
                    _buildBookingNotesCard(),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Booking Summary'),
                    const SizedBox(height: 8),
                    _buildBookingSummaryDetails(),
                    const SizedBox(height: 12),
                    _buildSectionTitle('Payment Method'),
                    const SizedBox(height: 6),
                    if (!_lockServiceAndPayment) ...[const SizedBox(height: 6)],
                    _buildAddPaymentCard(),
                    if (_showPaymentMethods && !_lockServiceAndPayment) ...[
                      const SizedBox(height: 8),
                      _buildPaymentMethodList(),
                    ],
                  ],
                ),
              );
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                opacity: _modalSheetScrimVisible ? 1 : 0,
                child: const ColoredBox(
                  color: Color(0x8A000000),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Material(
          color: Colors.white,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ElevatedButton(
                onPressed: _canConfirmBooking
                    ? (_isEditingBooking
                          ? _saveBookingChanges
                          : _confirmBooking)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _actionGold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(_isEditingBooking ? 'Save' : 'Place Booking & Pay'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleBookingTimeCard() {
    final dateLabel = intl.DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    final startLabel = _formatTimeOfDay(_selectedStartTimeValue);
    final endLabel = _formatTimeOfDay(_selectedEndTimeValue);
    final bool canEdit = _isEditingBooking && _isBookInAdvance;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryRow(label: 'Selected date', amount: dateLabel),
              const Divider(height: 16, color: Color(0x1A000000)),
              _buildSummaryRow(
                label: 'Selected time',
                amount: '$startLabel - $endLabel',
              ),
            ],
          ),
        ),
        if (canEdit)
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Icon(Icons.chevron_right, size: 18, color: Colors.black26),
          ),
      ],
    );

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
      ),
      child: content,
    );

    if (!canEdit) return card;
    return InkWell(
      onTap: _openScheduleBookingTimeSheet,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }

  Widget _buildProfileHeader({
    required String location,
    String? defaultAddress,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultProfileAvatar(
            radius: 32,
            photoUrl: widget.caregiver.photoUrl,
            label: widget.caregiver.name,
            backgroundColor: const Color.fromARGB(255, 181, 212, 212),
            accentColor: _tealAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.caregiver.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: Color(0xFFF4B63D),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.caregiver.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Caregiver',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 14, color: Colors.black45),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (defaultAddress?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 14, color: Colors.black45),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          defaultAddress!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.caregiver.specialization.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.caregiver.specialization,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard() {
    final person = _currentPerson;
    final selectedAddress = _activeAddress;
    final addressText = selectedAddress.addressLine?.isNotEmpty == true
        ? selectedAddress.addressLine!
        : selectedAddress.subtitle;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(person.id)
          .snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? {};
        final userLabel = (userData['label'] as String?)?.trim() ?? '';
        String labelText = userLabel;
        if (labelText.isEmpty) {
          labelText = selectedAddress.label?.trim() ?? '';
        }
        if (labelText.isEmpty) {
          labelText = person.label?.trim() ?? '';
        }
        if (_isEditingBooking) {
          labelText = '';
        }
        final card = Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DefaultProfileAvatar(
                radius: 32,
                photoUrl: person.photoUrl,
                label: person.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            person.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Client',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    if (addressText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.place,
                            size: 14,
                            color: Colors.black45,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              addressText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_canUseAddressPicker)
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
        );

        if (!_canUseAddressPicker) return card;
        return InkWell(
          onTap: _openAddressSelector,
          borderRadius: BorderRadius.circular(16),
          child: card,
        );
      },
    );
  }

  Future<void> _openAddressSelector() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileAddressesScreen(
          selectionMode: true,
          selectionModeForBookingEdit: true,
        ),
      ),
    );
    if (result == null) return;
    final selectedMap = Map<String, dynamic>.from(result);
    final selectedItem = AddressItem.fromMap(selectedMap);
    setState(() {
      _activeAddress = selectedItem;
      final selectedName = (selectedMap['name'] ?? selectedItem.title)
          ?.toString();
      final selectedLabel =
          (selectedMap['label'] ?? selectedMap['forWho'] ?? selectedItem.label)
              ?.toString();
      final selectedPhone = selectedMap['phone']?.toString();
      final selectedPhoto =
          (selectedMap['photoUrl'] ??
                  selectedMap['avatarUrl'] ??
                  selectedMap['profilePhoto'] ??
                  selectedMap['profileImageUrl'])
              ?.toString();
      _currentPerson = PersonProfile(
        id: selectedMap['id']?.toString() ?? _currentPerson.id,
        name: (selectedName?.trim().isNotEmpty ?? false)
            ? selectedName!.trim()
            : _currentPerson.name,
        age: _currentPerson.age,
        address: selectedItem.addressLine?.trim().isNotEmpty == true
            ? selectedItem.addressLine!
            : selectedItem.subtitle,
        conditions: _currentPerson.conditions,
        photoUrl: (selectedPhoto?.trim().isNotEmpty ?? false)
            ? selectedPhoto!.trim()
            : _currentPerson.photoUrl,
        label: (selectedLabel?.trim().isNotEmpty ?? false)
            ? selectedLabel!.trim()
            : _currentPerson.label,
        phone: (selectedPhone?.trim().isNotEmpty ?? false)
            ? selectedPhone!.trim()
            : _currentPerson.phone,
        notes: _currentPerson.notes,
        latitude: selectedItem.lat,
        longitude: selectedItem.long,
      );
    });
  }

  Future<void> _openScheduleBookingTimeSheet() async {
    if (!_isBookInAdvance) return;
    if (!_isEditingBooking) return;

    final initialStart = _bookInAdvanceStartOverride ?? _selectedStartTimeValue;
    final initialEnd = _bookInAdvanceEndOverride ?? _selectedEndTimeValue;
    setState(() => _modalSheetScrimVisible = true);
    ScheduleBookingResult? result;
    try {
      result = await showScheduleBookingTelegramSheet(
        context: context,
        caregiverId: widget.caregiver.id,
        initialDay: _normalizeDate(_selectedDate),
        initialStart: initialStart,
        initialEnd: initialEnd,
        primaryColor: _actionGold,
        excludeBookingId: widget.editingBookingId,
        allowInitialDayEvenIfUnavailable: true,
        barrierColor: Colors.transparent,
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
    final confirmed = result;
    if (confirmed == null) return;

    _setStateAndRefreshScheduleSheet(() {
      _selectedDate = confirmed.day;
      _scheduleAnchorDate = _normalizeDate(confirmed.day);
      _bookInAdvanceStartOverride = confirmed.start;
      _bookInAdvanceEndOverride = confirmed.end;
    });
  }

  Widget _buildSectionTitle(String text) {
    return Text(text, style: _sectionLabelTextStyle);
  }

  Widget _buildScheduleChips({
    List<DateTimeRange>? blockedDateRanges,
    Set<int>? disabledWeekdays,
  }) {
    final days = _scheduleDays;
    final ranges = blockedDateRanges ?? const <DateTimeRange>[];
    final disabledDays = disabledWeekdays ?? const <int>{};
    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = max(
            0.0,
            (constraints.maxWidth - _scheduleChipWidth) / 2,
          );
          if (_scheduleViewportWidth != constraints.maxWidth) {
            _scheduleViewportWidth = constraints.maxWidth;
            _scheduleAutoCentered = false;
            _scheduleCenterKey = null;
          }
          _scheduleSidePadding = horizontalPadding;
          final layoutDays = days
              .where((day) => !_isDateBlocked(day, ranges))
              .where((day) => !disabledDays.contains(day.weekday))
              .where(
                (day) =>
                    _weeklyTimeRanges.isEmpty ||
                    _weeklyTimeRanges.containsKey(day.weekday),
              )
              .toList();

          final normalizedSelected = _normalizeDate(_selectedDate);
          final shouldIncludeSelected =
              !_isDateBlocked(normalizedSelected, ranges) &&
              !disabledDays.contains(normalizedSelected.weekday) &&
              (_weeklyTimeRanges.isEmpty ||
                  _weeklyTimeRanges.containsKey(normalizedSelected.weekday));
          if (shouldIncludeSelected &&
              !layoutDays.any((d) => _isSameDay(d, normalizedSelected))) {
            layoutDays.add(normalizedSelected);
            layoutDays.sort((a, b) => a.compareTo(b));
          }

          final centerKey = [
            ranges.length,
            disabledDays.length,
            layoutDays.length,
            normalizedSelected.year,
            normalizedSelected.month,
            normalizedSelected.day,
          ].join('|');

          _scheduleLayoutDaysSnapshot = layoutDays;
          _scheduleRangesSnapshot = ranges;
          _scheduleDisabledWeekdaysSnapshot = disabledDays;

          final firstAllowedIndex = layoutDays.indexWhere(
            (d) => !_isPastDate(d),
          );
          if (firstAllowedIndex <= 0) {
            _scheduleMinOffset = 0;
          } else {
            final desiredMinCenter =
                (firstAllowedIndex * _scheduleChipSpacing) +
                _scheduleSidePadding +
                (_scheduleChipWidth / 2);
            final desiredMinOffset =
                desiredMinCenter - (constraints.maxWidth / 2);
            _scheduleMinOffset = max(0.0, desiredMinOffset);
          }

          if ((_scheduleCenterKey != centerKey || !_scheduleAutoCentered) &&
              constraints.maxWidth > 0) {
            _scheduleCenterKey = centerKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scheduleAutoCentered = true;
              _scrollToSelectedDateIndex(
                layoutDays: layoutDays,
                ranges: ranges,
                disabledWeekdays: disabledDays,
                animate: false,
              );
              if (_scheduleScrollController.hasClients &&
                  _scheduleScrollController.offset < _scheduleMinOffset) {
                _scheduleScrollController.jumpTo(_scheduleMinOffset);
              }
            });
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification &&
                      !_scheduleScrollAnimating &&
                      _scheduleScrollController.hasClients) {
                    final offset = _scheduleScrollController.offset;
                    if (offset < _scheduleMinOffset) {
                      _scheduleScrollController.jumpTo(_scheduleMinOffset);
                      return true;
                    }

                    _scheduleSnapDebounce?.cancel();
                    _scheduleSnapDebounce = Timer(
                      const Duration(milliseconds: 30),
                      () {
                        if (!mounted ||
                            _scheduleScrollAnimating ||
                            !_scheduleScrollController.hasClients) {
                          return;
                        }
                        _handleScheduleScrollEnd(
                          _scheduleRangesSnapshot,
                          _scheduleDisabledWeekdaysSnapshot,
                          _scheduleLayoutDaysSnapshot,
                        );
                      },
                    );

                    if (notification.dragDetails == null &&
                        _scheduleLayoutDaysSnapshot.isNotEmpty) {
                      final viewport =
                          _scheduleScrollController.position.viewportDimension;
                      if (viewport > 0) {
                        final center =
                            _scheduleScrollController.offset + (viewport / 2);
                        final index = _nearestScheduleIndex(
                          layoutDays: _scheduleLayoutDaysSnapshot,
                          center: center,
                        );
                        final itemCenter =
                            _scheduleSidePadding +
                            (index * _scheduleChipSpacing) +
                            (_scheduleChipWidth / 2);
                        final distance = (itemCenter - center).abs();
                        if (distance <= 48 &&
                            _scheduleLastSnappedIndex != index) {
                          _scheduleLastSnappedIndex = index;
                          _scrollToDateIndex(index);
                        }
                      }
                    }
                  }
                  if (notification is UserScrollNotification &&
                      notification.direction == ScrollDirection.idle) {
                    _handleScheduleScrollEnd(ranges, disabledDays, layoutDays);
                  }
                  if (notification is ScrollEndNotification) {
                    _scheduleSnapDebounce?.cancel();
                    _handleScheduleScrollEnd(ranges, disabledDays, layoutDays);
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scheduleScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: _scheduleScrollPhysics,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  itemExtent: _scheduleChipSpacing,
                  cacheExtent: _scheduleChipSpacing * 12,
                  itemCount: layoutDays.length,
                  itemBuilder: (context, index) {
                    final date = layoutDays[index];
                    final bool disabled = _isDateDisabled(
                      date,
                      ranges,
                      disabledDays,
                    );
                    final chipOpacity = disabled ? 0.55 : 1.0;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Opacity(
                        opacity: chipOpacity,
                        child: RepaintBoundary(
                          child: Container(
                            width: _scheduleChipWidth,
                            decoration: BoxDecoration(
                              color: disabled ? Colors.grey[100] : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _weekdayFormatter.format(date),
                                  style: TextStyle(
                                    color: Colors.black54.withValues(
                                      alpha: disabled ? 0.4 : 1,
                                    ),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _dayFormatter.format(date).padLeft(2, '0'),
                                  style: TextStyle(
                                    color: Colors.black54.withValues(
                                      alpha: disabled ? 0.4 : 1,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: _scheduleChipWidth,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _tealAccent, width: 1.5),
                    color: Colors.transparent,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimeChips() {
    if (_isBookInAdvance && _weeklyTimeRanges.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_timeOptions.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: Text(
            'No available times.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = max(
            0.0,
            (constraints.maxWidth - _timeChipWidth) / 2,
          );
          if (_timeViewportWidth != constraints.maxWidth) {
            _timeViewportWidth = constraints.maxWidth;
            _timeAutoCentered = false;
            _timeCenterKey = null;
          }
          _timeSidePadding = horizontalPadding;

          final firstAllowedIndex = _timeOptions.indexWhere(
            (t) => !_isTimeDisabled(t),
          );
          if (firstAllowedIndex <= 0) {
            _timeMinOffset = 0;
          } else {
            final desiredMinCenter =
                (firstAllowedIndex * _timeChipSpacing) +
                _timeSidePadding +
                (_timeChipWidth / 2);
            final desiredMinOffset =
                desiredMinCenter - (constraints.maxWidth / 2);
            _timeMinOffset = max(0.0, desiredMinOffset);
          }

          final centerKey = [
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _timeOptions.length,
            firstAllowedIndex,
          ].join('|');

          if ((_timeCenterKey != centerKey || !_timeAutoCentered) &&
              constraints.maxWidth > 0) {
            _timeCenterKey = centerKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _timeAutoCentered = true;
              if (firstAllowedIndex >= 0 &&
                  _selectedTimeIndex < firstAllowedIndex) {
                setState(() => _selectedTimeIndex = firstAllowedIndex);
              }
              _scrollToSelectedTimeIndex(animate: false);
              if (_timeScrollController.hasClients &&
                  _timeScrollController.offset < _timeMinOffset) {
                _timeScrollController.jumpTo(_timeMinOffset);
              }
            });
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification &&
                      !_timeScrollAnimating &&
                      _timeScrollController.hasClients) {
                    final offset = _timeScrollController.offset;
                    if (offset < _timeMinOffset) {
                      _timeScrollController.jumpTo(_timeMinOffset);
                      return true;
                    }
                    _timeSnapDebounce?.cancel();
                    _timeSnapDebounce = Timer(
                      const Duration(milliseconds: 30),
                      () {
                        if (!mounted ||
                            _timeScrollAnimating ||
                            !_timeScrollController.hasClients) {
                          return;
                        }
                        _handleTimeScrollEnd();
                      },
                    );
                  }
                  if (notification is ScrollEndNotification) {
                    _timeSnapDebounce?.cancel();
                    _handleTimeScrollEnd();
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _timeScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: _scheduleScrollPhysics,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  itemExtent: _timeChipSpacing,
                  cacheExtent: _timeChipSpacing * 12,
                  itemCount: _timeOptions.length,
                  itemBuilder: (context, index) {
                    final time = _timeOptions[index];
                    final disabled = _isTimeDisabled(time);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Opacity(
                        opacity: disabled ? 0.5 : 1,
                        child: RepaintBoundary(
                          child: Container(
                            width: _timeChipWidth,
                            decoration: BoxDecoration(
                              color: disabled ? Colors.grey[100] : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Center(
                              child: Text(
                                _formatTimeOfDay(time),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87.withValues(
                                    alpha: disabled ? 0.4 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: _timeChipWidth,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _tealAccent, width: 1.5),
                    color: Colors.transparent,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final suffix = time.period == DayPeriod.am ? 'am' : 'pm';
    final minute = time.minute.toString().padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  String _sanitizeToyyibText(
    String value, {
    required int maxLength,
    bool collapseSpaces = true,
  }) {
    // Keep it simple: allow alphanumeric + space + underscore + dash + dot + comma.
    final sanitized =
        value.replaceAll(RegExp(r"[^A-Za-z0-9 _\\-\\.,]"), " ").trim();
    final collapsed = collapseSpaces
        ? sanitized.replaceAll(RegExp(r"\\s+"), " ")
        : sanitized;
    if (collapsed.length <= maxLength) return collapsed;
    return collapsed.substring(0, maxLength).trim();
  }

  double? _coerceToDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<Map<String, dynamic>?> _fetchServiceDetails(String serviceName) async {
    final cached = _serviceCatalogByName[serviceName];
    if (cached != null) return cached;
    final snapshot =
        await FirebaseFirestore.instance
            .collection('services')
            .where('name', isEqualTo: serviceName)
            .limit(1)
            .get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data();
  }

  Future<void> _showServiceDetailsSheet(String serviceName) async {
    final theme = Theme.of(context);
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: false,
        isDismissible: true,
        enableDrag: false,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final bottomInset = mediaQuery.viewInsets.bottom;
          return SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 14 + bottomInset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Service Details',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _bookingAppBarText,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                splashRadius: 18,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _fetchServiceDetails(serviceName),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 22, bottom: 18),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final data = snapshot.data;
                            final name = (data?['name'] as String?)?.trim();
                            final description =
                                (data?['description'] as String?) ??
                                (data?['descriptions'] as String?) ??
                                (kServiceDescriptions[serviceName] ??
                                    'No description available.');
                            final imageUrl =
                                (data?['imageUrl'] as String?)?.trim() ??
                                (data?['image'] as String?)?.trim() ??
                                '';
                            final price =
                                _coerceToDouble(data?['price']) ??
                                _coerceToDouble(data?['amount']);
                            final per = (data?['per'] as String?)?.trim();

                            final priceLabel = price == null
                                ? null
                                : 'RM ${price.toStringAsFixed(2)}';
                            final perLabel =
                                (per == null || per.isEmpty) ? null : per;

                            Widget imageWidget;
                            if (imageUrl.isNotEmpty) {
                              imageWidget = Image.network(
                                imageUrl,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    color: Colors.grey[100],
                                    child: const Center(
                                      child: Icon(
                                        Icons.room_service_outlined,
                                        color: Colors.black26,
                                        size: 40,
                                      ),
                                    ),
                                  );
                                },
                              );
                            } else {
                              imageWidget = Container(
                                width: double.infinity,
                                height: 200,
                                color: Colors.grey[100],
                                child: const Center(
                                  child: Icon(
                                    Icons.room_service_outlined,
                                    color: Colors.black26,
                                    size: 40,
                                  ),
                                ),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RepaintBoundary(child: imageWidget),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    0,
                                  ),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 420),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          (name == null || name.isEmpty)
                                              ? serviceName
                                              : name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: _bookingAppBarText,
                                          ),
                                        ),
                                        if (priceLabel != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Text(
                                              perLabel == null
                                                  ? priceLabel
                                                  : '$priceLabel / $perLabel',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 10),
                                          child: Text(
                                            description,
                                            textAlign: TextAlign.justify,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.45,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Widget _buildServiceRow({required String service}) {
    final selected = _selectedService == service;
    final bool canSelect = !_lockServiceAndPayment;
    final details = _serviceCatalogByName[service];
    final imageUrl = (details?['imageUrl'] as String?)?.trim() ?? '';
    final price = _coerceToDouble(details?['price']);
    final per = (details?['per'] as String?)?.trim();
    final String? priceLabel = price == null ? null : 'RM ${price.toStringAsFixed(2)}';
    final String? perLabel = (per == null || per.isEmpty) ? null : per;
    final String secondaryText = priceLabel == null
        ? 'RM --'
        : (perLabel == null ? priceLabel : '$priceLabel / $perLabel');
    const Color accent = Color(0xFF00A8A7);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.grey[300]!,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.03),
              blurRadius: selected ? 12 : 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (canSelect) setState(() => _selectedService = service);
                _showServiceDetailsSheet(service);
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: accent.withValues(alpha: 0.1),
                child: (imageUrl.isNotEmpty)
                    ? ClipOval(
                        child: Image.network(
                          imageUrl,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.room_service_outlined,
                              color: accent,
                              size: 18,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.room_service_outlined,
                        color: accent,
                        size: 18,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (canSelect) setState(() => _selectedService = service);
                      _showServiceDetailsSheet(service);
                    },
                    child: Text(
                      service,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    secondaryText,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : Colors.grey,
                  width: 1.5,
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!canSelect) return;
                  setState(() => _selectedService = service);
                },
                child: selected
                    ? const Icon(Icons.check, size: 16, color: accent)
                    : null,
              ),
            ),
            if (!canSelect)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: Colors.black26,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingSummaryDetails() {
    final dateLabel = intl.DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    final timeLabel = _formatTimeOfDay(_selectedStartTimeValue);
    final endTimeLabel = _formatTimeOfDay(_selectedEndTimeValue);
    final selectedServiceName = _selectedService.isEmpty
        ? 'General care'
        : _selectedService;
    final servicePriceValue = _selectedServicePriceValue();
    final perLabel = _selectedServicePerLabel();
    final servicePriceLabel = 'RM ${servicePriceValue.toStringAsFixed(2)}'
        '${perLabel == null ? '' : ' / $perLabel'}';
    final distanceKmValue = _distanceKmValue();
    final distanceChargeValue = _distanceChargeValue();
    final totalValue = (servicePriceValue + distanceChargeValue).clamp(0, 999999);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryRow(label: 'Date', amount: dateLabel),
          if (_isBookInAdvance) ...[
            _buildSummaryRow(label: 'Start time', amount: timeLabel),
            _buildSummaryRow(label: 'End time', amount: endTimeLabel),
          ] else
            _buildSummaryRow(label: 'Time', amount: timeLabel),
          _buildSummaryRow(label: 'Service', amount: selectedServiceName),
          _buildSummaryRow(
            label: 'Service Price',
            amount: servicePriceLabel,
          ),
          _buildSummaryRow(
            label: 'Distance',
            amount: '${distanceKmValue.toStringAsFixed(1)} km',
          ),
          _buildSummaryRow(
            label: 'Distance Charge',
            amount: 'RM ${distanceChargeValue.toStringAsFixed(2)}',
          ),
          const Divider(height: 1, color: Colors.grey),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                'RM ${totalValue.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingNotesCard() {
    final locked = _lockServiceAndPayment;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _bookingNotesController,
        enabled: !locked,
        maxLines: 3,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add instructions for the caregiver…',
          hintStyle: const TextStyle(fontSize: 12, color: Colors.black45),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildSelectedScheduleSummaryCard() {
    final dateLabel = intl.DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
      ),
      child: _buildSummaryRow(label: 'Selected date', amount: dateLabel),
    );
  }

  Widget _buildSelectedTimeSummaryCard() {
    final startLabel = _formatTimeOfDay(_selectedStartTimeValue);
    final endLabel = _formatTimeOfDay(_selectedEndTimeValue);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
      ),
      child: _buildSummaryRow(
        label: 'Selected time',
        amount: '$startLabel - $endLabel',
      ),
    );
  }

  static const List<Map<String, dynamic>> _paymentMethods = [
    {
      'title': 'ToyyibPay',
      'label': 'TP',
      'color': Color(0xFF1A73E8),
      'asset': 'assets/images/toyyib_logo.png',
    },
  ];

  Widget _buildPaymentMethodList() {
    if (_lockServiceAndPayment) {
      return const SizedBox.shrink();
    }
    return Column(
      children: _paymentMethods.map((method) {
        final title = method['title'] as String;
        final label = method['label'] as String;
        final color = method['color'] as Color;
        final asset = method['asset'] as String?;
        final bool selected = _selectedPaymentMethod == title;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onTap: () => setState(() => _selectedPaymentMethod = title),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? const Color(0xFF00A8A7) : Colors.grey[300]!,
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: selected ? 0.08 : 0.03,
                    ),
                    blurRadius: selected ? 12 : 4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: asset != null
                        ? ClipOval(
                            child: Image.asset(
                              asset,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: label.length > 2 ? 10 : 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? const Color(0xFF00A8A7) : Colors.grey,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Color(0xFF00A8A7),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddPaymentCard() {
    final locked = _lockServiceAndPayment;
    final displayLabel = _selectedPaymentMethod ?? 'Payment methods available';
    final cardContent = Row(
      children: [
        Icon(
          Icons.credit_card_rounded,
          color: locked ? Colors.grey : const Color(0xFF00B8C6),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            locked ? '$displayLabel (locked)' : displayLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (locked)
          const Icon(Icons.lock_outline, size: 16, color: Colors.black26),
      ],
    );

    if (locked) {
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: cardContent,
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _showPaymentMethods = !_showPaymentMethods),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: cardContent,
      ),
    );
  }

  Widget _buildAddServiceCard() {
    final locked = _lockServiceAndPayment;
    final displayLabel = _selectedService.isNotEmpty
        ? _selectedService
        : 'Add services';
    final cardContent = Row(
      children: [
        Icon(
          Icons.room_service_outlined,
          color: locked ? Colors.grey : _tealAccent,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            locked ? '$displayLabel (locked)' : displayLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (locked)
          const Icon(Icons.lock_outline, size: 16, color: Colors.black26),
      ],
    );

    if (locked) {
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: cardContent,
      );
    }

    return GestureDetector(
      onTap: () =>
          setState(() => _showServicePreferences = !_showServicePreferences),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: cardContent,
      ),
    );
  }

  Widget _buildSummaryRow({required String label, required String amount}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Flexible(
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String _buildLocation(Map<String, dynamic> data) {
    final addresses = _extractAddressList(data['address'] ?? data['addresses']);
    if (addresses.isNotEmpty) {
      final primary = addresses.first;
      final fromAddress =
          _stringValue(primary['address']) ??
          _stringValue(primary['addressLine']);
      if (fromAddress?.isNotEmpty == true) {
        return fromAddress!;
      }
    }

    final value = <String>[];
    final city = _stringValue(data['city']) ?? _stringValue(data['address']);
    final state = _stringValue(data['state']) ?? _stringValue(data['location']);
    final country = _stringValue(data['country']);
    if (city?.isNotEmpty == true) value.add(city!);
    if (state?.isNotEmpty == true) value.add(state!);
    if (country?.isNotEmpty == true) value.add(country!);
    return value.join(', ');
  }

  String? _stringValue(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is GeoPoint) return null;
    if (value is Iterable) {
      final joinable = value.whereType<String>().toList();
      if (joinable.isNotEmpty) return joinable.join(', ');
    }
    if (value != null) return value.toString();
    return null;
  }

  String _formatCurrency(double value, {bool negative = false}) {
    final formatted = 'RM ${value.toStringAsFixed(2)}';
    return negative ? '- $formatted' : formatted;
  }

  List<String> _safeStringList(dynamic value) {
    if (value is Iterable) {
      return value.whereType<String>().toList();
    }
    if (value is String && value.isNotEmpty) return [value];
    return const <String>[];
  }

  List<DateTimeRange> _parseBlockedDateRanges(dynamic raw) {
    if (raw is Iterable) {
      final ranges = <DateTimeRange>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final start = _parseAvailabilityDate(entry['start']);
          final end = _parseAvailabilityDate(entry['end']);
          if (start != null && end != null) {
            ranges.add(
              DateTimeRange(
                start: _normalizeDate(start),
                end: _normalizeDate(end),
              ),
            );
          }
        }
      }
      return ranges;
    }
    return const <DateTimeRange>[];
  }

  DateTime? _parseAvailabilityDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  Set<int> _parseUnavailableWeekdays(dynamic raw) {
    final result = <int>{};
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);

        final dynamic availableRaw = map['available'];
        final bool? isAvailable = switch (availableRaw) {
          final bool v => v,
          final String v =>
            v.toLowerCase() == 'true'
                ? true
                : v.toLowerCase() == 'false'
                ? false
                : null,
          final num v => v != 0,
          _ => null,
        };

        final dayName = (map['day'] as String?)?.trim();
        if (dayName == null || dayName.isEmpty) continue;

        final weekday = _weekdayFromName(dayName);
        if (weekday != null && isAvailable == false) {
          result.add(weekday);
        }
      }
    }
    return result;
  }

  Map<int, _WeeklyTimeRange> _parseWeeklyTimeRanges(dynamic raw) {
    final result = <int, _WeeklyTimeRange>{};
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);

        final dayName = (map['day'] as String?)?.trim();
        if (dayName == null || dayName.isEmpty) continue;
        final weekday = _weekdayFromName(dayName);
        if (weekday == null) continue;

        final dynamic availableRaw = map['available'];
        final bool? isAvailable = switch (availableRaw) {
          final bool v => v,
          final String v =>
            v.toLowerCase() == 'true'
                ? true
                : v.toLowerCase() == 'false'
                ? false
                : null,
          final num v => v != 0,
          _ => null,
        };
        if (isAvailable != true) continue;

        final startRaw = (map['start'] as String?)?.trim();
        final endRaw = (map['end'] as String?)?.trim();
        final start = _parseTimeOfDay(startRaw);
        final end = _parseTimeOfDay(endRaw);
        if (start == null || end == null) continue;

        result[weekday] = _WeeklyTimeRange(start: start, end: end);
      }
    }
    return result;
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  List<TimeOfDay> _generateTimeSlots({
    required TimeOfDay start,
    required TimeOfDay end,
    required int minuteInterval,
  }) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (minuteInterval <= 0 || endMinutes <= startMinutes) return const [];

    int first = startMinutes;
    if (first % minuteInterval != 0) {
      first = ((first ~/ minuteInterval) + 1) * minuteInterval;
    }
    int last = endMinutes;
    last = (last ~/ minuteInterval) * minuteInterval;

    final slots = <TimeOfDay>[];
    for (int m = first; m < last; m += minuteInterval) {
      slots.add(TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
    }
    return slots;
  }

  int? _weekdayFromName(String name) {
    final lookup = {
      'monday': DateTime.monday,
      'mon': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'tue': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'wed': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'thu': DateTime.thursday,
      'friday': DateTime.friday,
      'fri': DateTime.friday,
      'saturday': DateTime.saturday,
      'sat': DateTime.saturday,
      'sunday': DateTime.sunday,
      'sun': DateTime.sunday,
    };
    return lookup[name.toLowerCase()];
  }

  bool _isDateBlocked(DateTime date, List<DateTimeRange> ranges) {
    for (final range in ranges) {
      final start = _normalizeDate(range.start);
      final end = _normalizeDate(range.end);
      if (!date.isBefore(start) && !date.isAfter(end)) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _extractAddressList(dynamic raw) {
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }
    if (raw is Iterable) {
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _clampToFuture(DateTime date) {
    final today = _normalizeDate(DateTime.now());
    final candidate = _normalizeDate(date);
    if (candidate.isBefore(today)) return today;
    return candidate;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isPastDate(DateTime date) {
    final today = _normalizeDate(DateTime.now());
    return _normalizeDate(date).isBefore(today);
  }

  bool _isTimeDisabled(TimeOfDay time) {
    if (!_isSameDay(_selectedDate, DateTime.now())) return false;
    final now = DateTime.now();
    final candidate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      time.hour,
      time.minute,
    );
    return candidate.isBefore(now);
  }

  Future<_ToyyibPayCheckout?> _createToyyibPayBill({
    required String serviceLabel,
    required double billingAmount,
    required Map<String, dynamic> bookingInfo,
    required String billName,
    required String billDescription,
  }) async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      final userSnapshot = authUser != null
          ? await FirebaseFirestore.instance
                .collection('users')
                .doc(authUser.uid)
                .get()
          : null;
      final userData = userSnapshot?.data();
      final payerName =
          _stringValue(userData?['name']) ??
          authUser?.displayName ??
          'ElderAssist User';
      final payerEmail =
          _stringValue(userData?['email']) ??
          authUser?.email ??
          'noreply@elderassist.com';
      final payerPhone =
          _stringValue(userData?['phone']) ??
          _stringValue(userData?['mobile']) ??
          authUser?.phoneNumber ??
          '0123456789';
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('createBookingAndPay');
      debugPrint(
        'ToyyibPay callable payload: billName=$billName, '
        'amount=$billingAmount (displayed price=${bookingInfo['servicePrice']})',
      );
      final response = await callable.call({
        ...bookingInfo,
        'billName': billName,
        'billDescription': billDescription,
        'amount': billingAmount,
        'name': payerName,
        'email': payerEmail,
        'phone': payerPhone,
      });
      debugPrint('ToyyibPay callable response: ${response.data}');
      final paymentUrl = response.data?['paymentUrl'] as String?;
      final bookingId = response.data?['bookingId'] as String?;
      final billCode = response.data?['billCode'] as String?;
      if (paymentUrl != null && paymentUrl.isNotEmpty) {
        return _ToyyibPayCheckout(
          bookingId: bookingId ?? '',
          billCode: billCode ?? '',
          paymentUrl: Uri.parse(paymentUrl),
        );
      }
      await _showPaymentErrorDialog(
        'ToyyibPay did not return a payment link. Please try again.',
      );
    } catch (err, stack) {
      final message = err is FirebaseFunctionsException
          ? err.message ?? err.code
          : err.toString();
      debugPrint('ToyyibPay create bill failed: $err\n$stack');
      await _showPaymentErrorDialog('Payment initialization failed: $message');
    }
    return null;
  }

  Future<void> _showPaymentErrorDialog(String message) async {
    if (_paymentSuccessDialogShown) return;
    if (!mounted) return;
    await _showPaymentDialog(title: 'Payment failed', message: message);
  }

  Future<void> _showPaymentResultDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final shouldRedirectToActivity =
        title.trim().toLowerCase() == 'payment successful';
    await _showPaymentDialog(
      title: title,
      message: message,
      onOk: shouldRedirectToActivity
          ? () {
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const UserRootScreen(
                    initialIndex: 3,
                    activityInitialCategoryIndex: 0,
                  ),
                ),
                (_) => false,
              );
            }
          : null,
    );
  }

  Future<void> _showPaymentDialog({
    required String title,
    required String message,
    VoidCallback? onOk,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.only(bottom: 12),
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onOk != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => onOk());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _actionGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToyyibPayCheckout {
  const _ToyyibPayCheckout({
    required this.bookingId,
    required this.billCode,
    required this.paymentUrl,
  });

  final String bookingId;
  final String billCode;
  final Uri paymentUrl;
}
