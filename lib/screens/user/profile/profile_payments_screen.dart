import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

const Color _tealAccent = Color(0xFF00A8A7);
const Color _cardBorderColor = Color(0xFFE0E0E0);
const Color _statusPaid = Color(0xFF2BB673);
const Color _statusPending = Color(0xFFF4B63D);
const Color _statusCancelled = Color(0xFFF25C54);
const double _segmentRadius = 26.0;
const double _segmentHeight = 38.0;
const Color _segmentIndicatorColor = Color(0xFFF4F5F7);
const BorderRadius _historyCardBorderRadius = BorderRadius.all(
  Radius.circular(18),
);
final BoxShadow _historyCardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.08),
  blurRadius: 16,
  offset: const Offset(0, 6),
);
final BoxShadow _segmentShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.04),
  blurRadius: 10,
  offset: const Offset(0, 4),
);

class ProfilePaymentsScreen extends StatefulWidget {
  const ProfilePaymentsScreen({super.key});

  @override
  State<ProfilePaymentsScreen> createState() => _ProfilePaymentsScreenState();
}

class _ProfilePaymentsScreenState extends State<ProfilePaymentsScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  final _formKey = GlobalKey<FormState>();
  final _bankController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _branchController = TextEditingController();
  String _payoutRole = 'client';
  bool _isSaving = false;
  Map<String, dynamic>? _savedDetails;

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
  }

  Future<void> _loadSavedDetails() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final data = snapshot.data()?['paymentDetails'] as Map<String, dynamic>?;
    if (data == null) return;
    setState(() {
      _savedDetails = data;
      _bankController.text = data['bankName'] ?? '';
      _accountNameController.text = data['accountName'] ?? '';
      _accountNumberController.text = data['accountNumber'] ?? '';
      _branchController.text = data['bankBranch'] ?? '';
      _payoutRole = data['payoutRole'] ?? 'client';
    });
  }

  Future<void> _savePaymentDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final callable = _functions.httpsCallable('savePaymentDetails');
      await callable.call({
        'bankName': _bankController.text.trim(),
        'accountName': _accountNameController.text.trim(),
        'accountNumber': _accountNumberController.text.trim(),
        'bankBranch': _branchController.text.trim(),
        'payoutRole': _payoutRole,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maklumat akaun disimpan')));
      await _loadSavedDetails();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal simpan: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _bankController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildProfileStyleAppBar(
        title: 'Payments & Billing',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                _buildSegmentTabBar(),
                const SizedBox(height: 14),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_paymentForm(), _historySection()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentTabBar() {
    return SizedBox(
      height: _segmentHeight,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(_segmentRadius),
              boxShadow: [_segmentShadow],
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_segmentRadius),
              child: TabBar(
                indicator: BoxDecoration(
                  color: _segmentIndicatorColor,
                  borderRadius: BorderRadius.circular(_segmentRadius),
                ),
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                tabs: const [
                  Tab(text: 'Payout Account'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payout Account',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Maklumat akaun ini akan digunakan untuk urusan refund atau withdraw.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _textField('Bank Name', _bankController),
                      const SizedBox(height: 12),
                      _textField('Account Holder', _accountNameController),
                      const SizedBox(height: 12),
                      _textField(
                        'Account Number',
                        _accountNumberController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _textField('Bank Branch (optional)', _branchController),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Client refund'),
                              selected: _payoutRole == 'client',
                              onSelected: (_) =>
                                  setState(() => _payoutRole = 'client'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Caregiver payout'),
                              selected: _payoutRole == 'caregiver',
                              onSelected: (_) =>
                                  setState(() => _payoutRole = 'caregiver'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _savePaymentDetails,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tealAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _isSaving ? 'Saving…' : 'Simpan Maklumat Payout',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_savedDetails != null) ...[
            const SizedBox(height: 16),
            _summaryCard(),
          ],
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Sila isi $label';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54),
        border: const UnderlineInputBorder(),
      ),
    );
  }

  Widget _summaryCard() {
    final data = _savedDetails!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Akaun disimpan',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${data['bankName']} • ${data['payoutRole']}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(data['accountName'] ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            data['accountNumber'] ?? '',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          if ((data['bankBranch'] ?? '').isNotEmpty)
            Text(
              data['bankBranch'],
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Widget _historySection() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();
    final stream = FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _historyPlaceholder('No payment history yet.');
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              _historyCard(docs[index].id, docs[index].data()),
        );
      },
    );
  }

  Widget _historyPlaceholder(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 38, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(String id, Map<String, dynamic> data) {
    final service = (data['service'] as String?) ?? 'Service';
    final amount = (data['servicePrice'] as num?)?.toDouble() ?? 0;
    final bookingStatus =
        (data['status'] as String?)?.toUpperCase() ?? 'PENDING';
    final paymentStatus =
        (data['paymentStatus'] as String?)?.toUpperCase() ?? bookingStatus;
    final reason = (data['cancellationReason'] as String?) ?? '';
    final personName = (data['personName'] as String?) ?? '';
    final caregiverName = (data['caregiverName'] as String?) ?? '';
    final personAddress = (data['personAddress'] as String?) ?? '';
    final caregiverPhoto = (data['caregiverPhoto'] as String?)?.trim() ?? '';
    final personPhoto = (data['personPhoto'] as String?)?.trim() ?? '';
    final date = (data['date'] as String?) ?? '';
    final time = (data['time'] as String?) ?? '';
    final notes = (data['notes'] as String?) ?? '';
    final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
    final showRefundInProgress =
        paymentStatus == 'REFUND_REQUESTED' || bookingStatus.contains('CANCEL');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _historyCardBorderRadius,
        border: Border.all(color: _cardBorderColor),
        boxShadow: [_historyCardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[200],
                child: Text(
                  (caregiverName.isNotEmpty
                          ? caregiverName[0]
                          : (service.isNotEmpty ? service[0] : '?'))
                      .toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caregiverName.isNotEmpty ? caregiverName : service,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (service.isNotEmpty && caregiverName.isNotEmpty)
                      Text(
                        service,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(
                bookingStatus: bookingStatus,
                paymentStatus: paymentStatus,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_month, size: 12, color: Colors.black54),
              const SizedBox(width: 4),
              Text(
                date.isNotEmpty ? date : '-',
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.access_time, size: 12, color: Colors.black54),
              const SizedBox(width: 4),
              Text(
                time.isNotEmpty ? time : '-',
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Reason: $reason',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.redAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                DefaultProfileAvatar(
                  radius: 16,
                  label: personName.isNotEmpty ? personName : caregiverName,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName.isNotEmpty ? personName : caregiverName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (personAddress.isNotEmpty)
                        Text(
                          personAddress,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'RM ${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const Spacer(),
              if (showRefundInProgress)
                const Text(
                  'Refund in progress (ToyyibPay)',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
            ],
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                notes,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.bookingStatus, required this.paymentStatus});

  final String bookingStatus;
  final String paymentStatus;

  String get _normalizedBooking => bookingStatus.trim().toLowerCase();
  String get _normalizedPayment => paymentStatus.trim().toLowerCase();

  bool get _isCancelled => _normalizedBooking.contains('cancel');
  bool get _isRefundRequested => _normalizedPayment == 'refund_requested';

  Color get _dotColor {
    if (_isCancelled) return _statusCancelled;
    if (_isRefundRequested) return _statusPending;
    return switch (_normalizedPayment) {
      'paid' || 'success' => _statusPaid,
      'failed' => _statusCancelled,
      'pending' => _statusPending,
      _ => Colors.grey.shade600,
    };
  }

  String get _label {
    if (_isCancelled) return 'Cancelled';
    if (_isRefundRequested) return 'Refund requested';
    return switch (_normalizedPayment) {
      'paid' || 'success' => 'Success',
      'failed' => 'Failed',
      'pending' => 'Pending',
      var other => _formatLabel(other),
    };
  }

  String _formatLabel(String raw) {
    final segments = raw
        .split(RegExp(r'[_\s-]+'))
        .where((segment) => segment.isNotEmpty)
        .map((segment) {
          final lower = segment.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .toList();
    return segments.isEmpty ? 'Status' : segments.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorderColor),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
