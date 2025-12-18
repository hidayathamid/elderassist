import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

import 'package:emergencies_disability_assistance_app/screens/user/user_root_screen.dart';
import 'booking_person_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_addresses_screen.dart';
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
  final String? editingBookingId;
  final String? lockedService;
  final String? lockedPaymentMethod;
  final bool readOnlyServiceAndPayment;
  final bool enableClientAddressSelection;

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
  late PersonProfile _currentPerson;
  late AddressItem _activeAddress;

  @override
  void initState() {
    super.initState();
    _currentPerson = widget.person;
    _activeAddress = widget.selectedAddress;
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
    if (widget.lockedService?.isNotEmpty == true) {
      _selectedService = widget.lockedService!;
    }
    _selectedPaymentMethod = widget.lockedPaymentMethod;
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

  bool get _isEditingBooking => widget.editingBookingId != null;

  bool get _lockServiceAndPayment => widget.readOnlyServiceAndPayment;

  bool get _canUseAddressPicker => widget.enableClientAddressSelection;

  bool get _canConfirmBooking {
    if (_isEditingBooking) return !_isLoading;
    return !_isLoading && _selectedPaymentMethod != null;
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
      final pickupDetails = _currentPerson.notes.trim();
      final firestore = FirebaseFirestore.instance;
      final bookingRef = firestore.collection('bookings').doc();
      final startTimeValue = _timeOptions[_selectedTimeIndex];
      final personAddress =
          (_activeAddress.addressLine ?? _activeAddress.subtitle).trim();
      final bookingData = {
        'bookingId': bookingRef.id,
        'userId': user.uid,
        'caregiverId': widget.caregiver.id,
        'caregiverName': widget.caregiver.name,
        'service': serviceLabel,
        'personId': _currentPerson.id,
        'personName': _currentPerson.name,
        'personAddress': personAddress,
        'addressId': _activeAddress.id,
        'date': _formatDate(_selectedDate),
        'time': _formatTimeOfDay(startTimeValue),
        'paymentMethod': _selectedPaymentMethod!,
        'servicePrice': widget.price,
        'status': _isBookInAdvance ? 'SCHEDULED' : 'ASSIGNED',
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

  Future<void> _saveBookingChanges() async {
    if (_isLoading || widget.editingBookingId == null) return;
    setState(() => _isLoading = true);
    try {
      final startTimeValue = _timeOptions[_selectedTimeIndex];
      final addressText =
          (_activeAddress.addressLine ?? _activeAddress.subtitle).trim();
      final updates = {
        'date': _formatDate(_selectedDate),
        'time': _formatTimeOfDay(startTimeValue),
        'personName': _currentPerson.name,
        'personAddress': addressText,
        'personId': _currentPerson.id,
        'personPhone': _currentPerson.phone,
        'addressLabel':
            _activeAddress.label ?? _currentPerson.label ?? '',
        'caregiverName': widget.caregiver.name,
        'addressId': _activeAddress.id,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.editingBookingId)
          .update(updates);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                if (!_lockServiceAndPayment) ...[
                  const Text(
                    'Select ToyyibPay or PayPal to continue.',
                    style: TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                ],
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
                onPressed: _canConfirmBooking
                    ? (_isEditingBooking ? _saveBookingChanges : _confirmBooking)
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
    final person = _currentPerson;
    final selectedAddress = _activeAddress;
    final labelText = selectedAddress.label?.trim().isNotEmpty == true
        ? selectedAddress.label!.trim()
        : (person.label?.trim() ?? '');
    final addressText = selectedAddress.addressLine?.isNotEmpty == true
        ? selectedAddress.addressLine!
        : selectedAddress.subtitle;
    final card = Container(
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
      final selectedName = (selectedMap['name'] ?? selectedItem.title)?.toString();
      final selectedLabel =
          (selectedMap['label'] ?? selectedMap['forWho'] ?? selectedItem.label)
              ?.toString();
      final selectedPhone = selectedMap['phone']?.toString();
      _currentPerson = PersonProfile(
        id: selectedMap['id']?.toString() ?? _currentPerson.id,
        name: (selectedName?.trim().isNotEmpty ?? false)
            ? selectedName!.trim()
            : _currentPerson.name,
        age: _currentPerson.age,
        address:
            selectedItem.addressLine?.trim().isNotEmpty == true
                ? selectedItem.addressLine!
                : selectedItem.subtitle,
        conditions: _currentPerson.conditions,
        photoUrl: _currentPerson.photoUrl,
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
    final bool canSelect = !_lockServiceAndPayment;
    final description = kServiceDescriptions[service] ?? 'Book now with doctor';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: canSelect ? () => setState(() => _selectedService = service) : null,
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
    final displayLabel =
        _selectedPaymentMethod ?? 'Add payment method';
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
          border: Border.all(color: Colors.grey[300]!),
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
          border: Border.all(color: Colors.grey[300]!),
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
