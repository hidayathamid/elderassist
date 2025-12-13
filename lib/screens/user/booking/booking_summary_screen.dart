import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import 'package:emergencies_disability_assistance_app/screens/user/user_root_screen.dart';
import 'booking_person_screen.dart';
import '../../../constants/service_options.dart';
import '../../../models/caregiver_model.dart';

const Color _tealAccent = Color(0xFF00A8A7);
const Color _actionGold = Color(0xFFF4B63D);
const TextStyle _dialogTitleStyle = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _dialogContentStyle = TextStyle(color: Colors.black87);

const Color _bookingAppBarText = Color(0xFF1B1D29);
const TextStyle _sectionLabelTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: Color(0xFF1B1D29),
);

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
  });

  final PersonProfile person;
  final CaregiverModel caregiver;
  final DateTime scheduleDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double price;
  final AddressItem selectedAddress;
  final bool showScheduleSection;

  @override
  State<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends State<BookingSummaryScreen> {
  bool _isLoading = false;
  String _selectedService = '';
  late DateTime _selectedDate;
  late List<TimeOfDay> _timeOptions;
  late int _selectedTimeIndex;
  late bool _isBookInAdvance;
  bool _showPaymentMethods = false;
  String? _selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.showScheduleSection
        ? _clampToFuture(widget.scheduleDate)
        : now;
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
  }

  Widget _buildLabeledBlock({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  bool get _canConfirmBooking => !_isLoading && _selectedPaymentMethod != null;

  Future<void> _confirmBooking() async {
    if (_isLoading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to place booking')),
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
      final serviceLabel = _selectedService.isEmpty
          ? 'General care'
          : _selectedService;
      final pickupDetails = widget.person.notes.trim();
      final firestore = FirebaseFirestore.instance;
      final bookingRef = firestore.collection('bookings').doc();
      final startTimeValue = _timeOptions[_selectedTimeIndex];
      final personAddress =
          (widget.selectedAddress.addressLine ??
                  widget.selectedAddress.subtitle)
              .trim();
      final bookingData = {
        'bookingId': bookingRef.id,
        'userId': user.uid,
        'caregiverId': widget.caregiver.id,
        'service': serviceLabel,
        'personId': widget.person.id,
        'personName': widget.person.name,
        'personAddress': personAddress,
        'date': _formatDate(_selectedDate),
        'scheduledDate': _formatDate(_selectedDate),
        'time': _formatTimeOfDay(startTimeValue),
        'startTime': _formatTime24(startTimeValue),
        'endTime': _formatTime24(_nextHour(startTimeValue)),
        'paymentMethod': _selectedPaymentMethod!,
        'servicePrice': widget.price,
        'status': 'PENDING',
        'notes': pickupDetails,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await bookingRef.set(bookingData);

      if (!mounted) return;
      await _showBookingSuccessDialog();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const UserRootScreen(initialIndex: 3),
        ),
        (route) => false,
      );
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

  Future<void> _showBookingSuccessDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Success',
          textAlign: TextAlign.center,
          style: _dialogTitleStyle,
        ),
        content: const Text(
          'Booking stored successfully.',
          textAlign: TextAlign.center,
          style: _dialogContentStyle,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
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
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime24(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  TimeOfDay _nextHour(TimeOfDay time) {
    final totalMinutes = time.hour * 60 + time.minute + 60;
    final hour = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  List<DateTime> get _scheduleDays {
    final anchor = _normalizeDate(_selectedDate);
    return List.generate(7, (index) {
      return anchor.add(Duration(days: index - 3));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Colors.white,
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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .doc(widget.caregiver.id)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          final location = _buildLocation(data);
          final serviceOptions = _safeStringList(
            data['services'],
          ).where((s) => s.trim().isNotEmpty).toList();
          final services = serviceOptions.isNotEmpty
              ? serviceOptions
              : widget.caregiver.services;
          if (_selectedService.isEmpty && services.isNotEmpty) {
            _selectedService = services.first;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 90),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Selected Caregiver & Client',
                    style: _sectionLabelTextStyle,
                  ),
                ),
                _buildLabeledBlock(
                  label: 'Caregiver',
                  child: _buildProfileHeader(location: location),
                ),
                const SizedBox(height: 6),
                _buildLabeledBlock(label: 'Client', child: _buildPersonCard()),
                const SizedBox(height: 16),
                if (_isBookInAdvance) ...[
                  _buildSectionTitle('Schedule'),
                  _buildScheduleChips(),
                  const SizedBox(height: 12),
                  _buildSectionTitle('Choose Time'),
                  _buildTimeChips(),
                  const SizedBox(height: 16),
                ],
                _buildSectionTitle('Select Service'),
                ...services.map(
                  (service) => _buildServiceRow(service: service),
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Booking Summary'),
                const SizedBox(height: 8),
                _buildBookingSummaryDetails(),
                const SizedBox(height: 12),
                const Text('Payment Method', style: _sectionLabelTextStyle),
                const SizedBox(height: 6),
                const Text(
                  'Select ToyyibPay or PayPal to continue.',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                _buildAddPaymentCard(),
                if (_showPaymentMethods) ...[
                  const SizedBox(height: 8),
                  _buildPaymentMethodList(),
                ],
              ],
            ),
          );
        },
      ),
      bottomSheet: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
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
                onPressed: _canConfirmBooking ? _confirmBooking : null,
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
                    : const Text('Place Booking & Pay'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader({required String location}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: widget.caregiver.photoUrl.isNotEmpty
                ? Colors.white
                : const Color.fromARGB(
                    255,
                    181,
                    212,
                    212,
                  ).withValues(alpha: 0.1),
            backgroundImage: widget.caregiver.photoUrl.isNotEmpty
                ? NetworkImage(widget.caregiver.photoUrl)
                : null,
            child: widget.caregiver.photoUrl.isEmpty
                ? Text(
                    widget.caregiver.name.isNotEmpty
                        ? widget.caregiver.name[0].toUpperCase()
                        : 'C',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _tealAccent,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.caregiver.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    for (int i = 0; i < 5; i++)
                      Icon(
                        Icons.star,
                        size: 10,
                        color: (widget.caregiver.rating >= i + 1)
                            ? Colors.amber
                            : Colors.grey[300],
                      ),
                    const SizedBox(width: 3),
                    Text(
                      widget.caregiver.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 12, color: Colors.black45),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            fontSize: 10,
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
    final person = widget.person;
    final selectedAddress = widget.selectedAddress;
    final labelText = selectedAddress.label?.trim().isNotEmpty == true
        ? selectedAddress.label!.trim()
        : (person.label?.trim() ?? '');
    final addressText = selectedAddress.addressLine?.isNotEmpty == true
        ? selectedAddress.addressLine!
        : selectedAddress.subtitle;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(
                  person.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (labelText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    labelText,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
                if (addressText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 12, color: Colors.black45),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          addressText,
                          style: const TextStyle(
                            fontSize: 10,
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
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(text, style: _sectionLabelTextStyle);
  }

  Widget _buildScheduleChips() {
    final days = _scheduleDays;
    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: List.generate(days.length, (index) {
            final date = days[index];
            final bool selected = _isSameDay(date, _selectedDate);
            final bool pastDate = _isPastDate(date);
            final chipOpacity = pastDate ? 0.55 : 1.0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Opacity(
                opacity: chipOpacity,
                child: GestureDetector(
                  onTap: pastDate
                      ? null
                      : () => setState(
                          () => _selectedDate = _clampToFuture(date),
                        ),
                  child: Container(
                    width: 52,
                    decoration: BoxDecoration(
                      color: selected
                          ? _tealAccent
                          : pastDate
                          ? Colors.grey[100]
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : pastDate
                            ? Colors.grey[200]!
                            : Colors.grey[300]!,
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
                          DateFormat('EEE').format(date),
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.black54.withValues(
                                    alpha: pastDate ? 0.4 : 1,
                                  ),
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('d').format(date).padLeft(2, '0'),
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.black.withValues(
                                    alpha: pastDate ? 0.4 : 1,
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
          }),
        ),
      ),
    );
  }

  Widget _buildTimeChips() {
    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: List.generate(_timeOptions.length, (index) {
            final time = _timeOptions[index];
            final selected = _selectedTimeIndex == index;
            final pastTime = _isPastTime(time);
            final chipOpacity = pastTime ? 0.45 : 1.0;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Opacity(
                opacity: chipOpacity,
                child: GestureDetector(
                  onTap: pastTime
                      ? null
                      : () => setState(() => _selectedTimeIndex = index),
                  child: Container(
                    width: 60,
                    decoration: BoxDecoration(
                      color: selected
                          ? _tealAccent
                          : pastTime
                          ? Colors.grey[100]
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : pastTime
                            ? Colors.grey[200]!
                            : Colors.grey[300]!,
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
                          color: selected
                              ? Colors.white
                              : Colors.black87.withValues(
                                  alpha: pastTime ? 0.4 : 1,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final suffix = time.period == DayPeriod.am ? 'am' : 'pm';
    final minute = time.minute.toString().padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  Widget _buildServiceRow({required String service}) {
    final selected = _selectedService == service;
    final description = kServiceDescriptions[service] ?? 'Book now with doctor';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedService = service),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF00A8A7) : Colors.grey[300]!,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F7FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.video_call_rounded,
                  color: Color(0xFF00A8A7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? const Color(0xFF00A8A7) : Colors.grey,
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
  }

  Widget _buildBookingSummaryDetails() {
    final dateLabel = DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    final timeLabel = _formatTimeOfDay(_timeOptions[_selectedTimeIndex]);
    final serviceLabel = _selectedService.isEmpty
        ? 'General care'
        : _selectedService;
    final servicePrice = widget.price;
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
          _buildSummaryRow(label: 'Time', amount: timeLabel),
          _buildSummaryRow(label: 'Service', amount: serviceLabel),
          const Divider(height: 1, color: Colors.grey),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Service Price',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                _formatCurrency(servicePrice),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
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
    {
      'title': 'PayPal',
      'label': 'PP',
      'color': Color(0xFF0B5BA1),
      'asset': 'assets/images/paypal_logo.png',
    },
  ];

  Widget _buildPaymentMethodList() {
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
    return GestureDetector(
      onTap: () => setState(() => _showPaymentMethods = !_showPaymentMethods),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: const [
            Icon(Icons.credit_card_rounded, color: Color(0xFF00B8C6), size: 20),
            SizedBox(width: 10),
            Text(
              'Add payment method',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
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
    return const [];
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
    if (_isBookInAdvance) return false;
    final today = _normalizeDate(DateTime.now());
    return _normalizeDate(date).isBefore(today);
  }

  bool _isPastTime(TimeOfDay time) {
    if (_isBookInAdvance) return false;
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
}
