import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/models/payment_document_target.dart';
import 'package:emergencies_disability_assistance_app/utils/service_preferences.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const Color _cardBorderColor = Color(0xFFE0E0E0);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _reminderIconColor = Color(0xFF00A8A7);
final TextStyle _payoutHintStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText.withValues(alpha: 0.45),
);
const Color _statusPaid = Color(0xFF2BB673);
const Color _statusCancelled = Color(0xFFF25C54);
const double _segmentRadius = 26.0;
const double _segmentHeight = 38.0;
const Color _segmentIndicatorColor = Color(0xFFF4F5F7);
const Color _receiptCardShadow = Color(0x1A0B0C10);
const Color _receiptCardBorderStrong = Color(0xFFE1E4EA);
const Color _receiptMutedText = Color(0xFF6B7280);
const BorderRadius _historyCardBorderRadius = BorderRadius.all(
  Radius.circular(18),
);
const double _historyCardSwipeMax = 200.0;
const double _historyCardSwipeThreshold = 120.0;
const Color _accentGold = Color(0xFFF4B63D);
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
const List<String> _malaysiaBanks = [
  'Affin Bank',
  'Alliance Bank',
  'AMBank',
  'Bank Islam',
  'Bank Muamalat',
  'Bank Rakyat',
  'Bank Simpanan Nasional',
  'CIMB Bank',
  'Hong Leong Bank',
  'HSBC',
  'Maybank',
  'Public Bank',
  'RHB Bank',
  'Standard Chartered',
  'UOB',
];

class ProfilePaymentsScreen extends StatefulWidget {
  final PaymentDocumentTarget target;
  final int initialTabIndex;
  final String? historyNotificationMessage;

  const ProfilePaymentsScreen({
    super.key,
    this.target = PaymentDocumentTarget.user,
    this.initialTabIndex = 0,
    this.historyNotificationMessage,
  });

  @override
  State<ProfilePaymentsScreen> createState() => _ProfilePaymentsScreenState();
}

class _ProfilePaymentsScreenState extends State<ProfilePaymentsScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final LayerLink _bankFieldLink = LayerLink();
  final GlobalKey _bankFieldKey = GlobalKey();
  OverlayEntry? _bankOverlayEntry;
  final TextEditingController _bankSearchController = TextEditingController();
  final TextEditingController _bankFieldController = TextEditingController();
  final FocusNode _bankSearchFocusNode = FocusNode();
  bool _isSaving = false;
  String? _selectedBank;
  String _initialBankName = '';
  String _initialAccountName = '';
  String _initialAccountNumber = '';
  bool _hasChanges = false;
  bool _isFormValid = false;
  DocumentReference<Map<String, dynamic>>? _activeTargetRef;
  bool _isCaregiverAccount = false;
  String? _historyNotificationMessage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _paymentDocsFromServer =
      const [];
  bool _hasSeenPaymentServerSnapshot = false;
  DateTime? _paymentsCacheFirstSeenAt;
  final Set<String> _hiddenPaymentIds = <String>{};
  final Set<String> _dismissedPaymentNotices = <String>{};
  Timestamp? _lastSeenPaymentHistoryAt;
  bool _historySeenInitialized = false;
  TabController? _tabController;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _withdrawDocsFromServer =
      const [];
  bool _hasSeenWithdrawServerSnapshot = false;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
  _legacyPaymentsByBookingFuture;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadLegacyPaymentsByBookingId(String userId) async {
    // Some legacy payment docs were created without `payments.userId`.
    // Fallback: resolve payments via the user's bookings (bookingId/toyyibBillCode).
    final bookingsSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .limit(80)
        .get();

    if (bookingsSnap.docs.isEmpty) return const [];

    final billCodes = <String>{};
    final bookingIds = <String>{};
    for (final doc in bookingsSnap.docs) {
      final data = doc.data();
      bookingIds.add(doc.id);
      final billCode =
          (data['toyyibBillCode'] as String?)?.trim() ??
          (data['billCode'] as String?)?.trim();
      if (billCode != null && billCode.isNotEmpty) billCodes.add(billCode);
    }

    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final payments = FirebaseFirestore.instance.collection('payments');

    // 1) Query by documentId in chunks (billCode is doc id for ToyyibPay).
    final billCodeList = billCodes.toList();
    for (var i = 0; i < billCodeList.length; i += 10) {
      final chunk = billCodeList.sublist(
        i,
        (i + 10).clamp(0, billCodeList.length),
      );
      if (chunk.isEmpty) continue;
      final q = await payments
          .where(FieldPath.documentId, whereIn: chunk)
          .limit(10)
          .get();
      results.addAll(q.docs);
    }

    // 2) Fallback: query by bookingId (in case billCode isn't stored).
    // Limit to a small number to avoid excessive reads.
    var scanned = 0;
    for (final bid in bookingIds) {
      if (scanned >= 40) break;
      scanned += 1;
      final q = await payments
          .where('bookingId', isEqualTo: bid)
          .limit(3)
          .get();
      for (final doc in q.docs) {
        results.add(doc);
      }
    }

    // Dedupe by id.
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in results) {
      byId[doc.id] = doc;
    }
    return byId.values.toList();
  }

  bool get _isCaregiverPov {
    if (widget.target == PaymentDocumentTarget.caregiver) return true;
    if (widget.target == PaymentDocumentTarget.user) return false;
    final ref = _activeTargetRef;
    if (ref == null) return _isCaregiverAccount;
    // user/<uid> vs caregivers/<uid>
    return ref.path.startsWith('caregivers/');
  }

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
    _accountNameController.addListener(_onFormFieldChanged);
    _accountNumberController.addListener(_onFormFieldChanged);
    _bankSearchController.addListener(_refreshBankOverlay);
    _historyNotificationMessage = widget.historyNotificationMessage;
  }

  void _handleTabChange() {
    final controller = _tabController;
    if (controller == null) return;
    if (controller.index != 1) return;
    if (controller.indexIsChanging) return;
    _markPaymentHistorySeen();
  }

  Stream<int> _newPaymentHistoryCountStream({
    required String userId,
    required DocumentReference<Map<String, dynamic>> targetRef,
  }) {
    if (userId.isEmpty) return Stream<int>.value(0);
    return targetRef.snapshots().asyncExpand((doc) {
      final lastSeen = doc.data()?['lastSeenPaymentHistoryAt'] as Timestamp?;
      if (lastSeen == null) return Stream<int>.value(0);
      _lastSeenPaymentHistoryAt = lastSeen;
      return FirebaseFirestore.instance
          .collection('payments')
          .where('userId', isEqualTo: userId)
          .where('updatedAt', isGreaterThan: lastSeen)
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .map((snap) {
            var count = 0;
            for (final payment in snap.docs) {
              final data = payment.data();
              if ((data['hidden'] as bool?) == true) continue;
              final status = (data['status'] as num?)?.toInt();
              final paymentStatus = (data['paymentStatus'] as String?)
                  ?.trim()
                  .toUpperCase();
              if (status == 3 || paymentStatus == 'FAILED') continue;
              count++;
            }
            return count;
          });
    }).distinct();
  }

  bool _isPaymentHiddenForUser(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    if ((data['hidden'] as bool?) == true) return true; // legacy global hide
    final hiddenFor = data['hiddenFor'];
    if (hiddenFor is Map) {
      final map = Map<String, dynamic>.from(hiddenFor);
      return map[userId] == true;
    }
    final hiddenForUsers = data['hiddenForUsers'];
    if (hiddenForUsers is Iterable) {
      return hiddenForUsers.whereType<Object>().any(
        (e) => e.toString() == userId,
      );
    }
    return false;
  }

  Future<void> _markPaymentHistorySeen() async {
    final ref = _activeTargetRef;
    if (ref == null) return;
    await ref.set({
      'lastSeenPaymentHistoryAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _lastSeenPaymentHistoryAt = Timestamp.now();
  }

  Future<void> _loadSavedDetails() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(userId);
    final caregiverSnap = await caregiverRef.get();
    final userSnap = await userRef.get();
    Map<String, dynamic>? data;
    DocumentReference<Map<String, dynamic>> resolvedRef = userRef;
    final bool caregiverExists = caregiverSnap.exists;
    switch (widget.target) {
      case PaymentDocumentTarget.caregiver:
        resolvedRef = caregiverRef;
        if (caregiverSnap.exists) {
          data =
              caregiverSnap.data()?['paymentDetails'] as Map<String, dynamic>?;
        }
        break;
      case PaymentDocumentTarget.user:
        resolvedRef = userRef;
        data = userSnap.data()?['paymentDetails'] as Map<String, dynamic>?;
        break;
      case PaymentDocumentTarget.auto:
        if (caregiverSnap.exists) {
          resolvedRef = caregiverRef;
          data =
              caregiverSnap.data()?['paymentDetails'] as Map<String, dynamic>?;
        }
        if (data == null) {
          resolvedRef = userRef;
          data = userSnap.data()?['paymentDetails'] as Map<String, dynamic>?;
        }
    }
    _activeTargetRef = resolvedRef;
    if (!_historySeenInitialized) {
      _historySeenInitialized = true;
      final resolvedSnap = await resolvedRef.get();
      final existingSeen = resolvedSnap.data()?['lastSeenPaymentHistoryAt'];
      final dismissedNoticesRaw = resolvedSnap
          .data()?['dismissedPaymentHistoryNotices'];
      if (dismissedNoticesRaw is Iterable) {
        _dismissedPaymentNotices
          ..clear()
          ..addAll(
            dismissedNoticesRaw
                .whereType<Object>()
                .map((e) => e.toString())
                .where((v) => v.trim().isNotEmpty),
          );
      }
      if (existingSeen is Timestamp) {
        _lastSeenPaymentHistoryAt = existingSeen;
      } else {
        await resolvedRef.set({
          'lastSeenPaymentHistoryAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _lastSeenPaymentHistoryAt = Timestamp.now();
      }
    }
    if (data == null) {
      if (!mounted) return;
      setState(() {
        _isCaregiverAccount = caregiverExists;
      });
      return;
    }
    final paymentData = data;
    setState(() {
      _selectedBank = paymentData['bankName'] as String?;
      _bankFieldController.text = _selectedBank ?? '';
      _accountNameController.text = paymentData['accountName'] ?? '';
      _accountNumberController.text = paymentData['accountNumber'] ?? '';
      _initialBankName = _selectedBank?.trim() ?? '';
      _initialAccountName = _accountNameController.text.trim();
      _initialAccountNumber = _accountNumberController.text.trim();
      _hasChanges = false;
      _isCaregiverAccount = caregiverExists;
    });
    _onFormFieldChanged();
  }

  Future<void> _savePaymentDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final callable = _functions.httpsCallable('savePaymentDetails');
      await callable.call({
        'bankName': _selectedBank ?? '',
        'accountName': _accountNameController.text.trim(),
        'accountNumber': _accountNumberController.text.trim(),
        'target': widget.target.name,
      });
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final paymentDetails = {
          'bankName': _selectedBank ?? '',
          'accountName': _accountNameController.text.trim(),
          'accountNumber': _accountNumberController.text.trim(),
        };
        final targetRef = _activeTargetRef ?? await _determineTargetRef(userId);
        await targetRef.set({
          'paymentDetails': paymentDetails,
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      await _loadSavedDetails();
    } catch (error) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChange);
    _accountNameController
      ..removeListener(_onFormFieldChanged)
      ..dispose();
    _accountNumberController
      ..removeListener(_onFormFieldChanged)
      ..dispose();
    _closeBankMenu();
    _bankSearchController
      ..removeListener(_refreshBankOverlay)
      ..dispose();
    _bankFieldController.dispose();
    _bankSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _handleBackPress();
        if (!shouldLeave) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: buildProfileStyleAppBar(
          title: 'Payments & Billing',
          onBack: _handleBackPress,
        ),
        body: SafeArea(
          child: DefaultTabController(
            initialIndex: widget.initialTabIndex.clamp(0, 1).toInt(),
            length: 2,
            child: Builder(
              builder: (tabContext) {
                final controller = DefaultTabController.of(tabContext);
                if (controller != _tabController) {
                  _tabController?.removeListener(_handleTabChange);
                  _tabController = controller..addListener(_handleTabChange);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _handleTabChange(),
                  );
                }
                return Padding(
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dismissPendingPaymentNotice(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final ref = _activeTargetRef;
    setState(() {
      _dismissedPaymentNotices.add(trimmed);
      if (_historyNotificationMessage?.trim() == trimmed) {
        _historyNotificationMessage = null;
      }
    });
    if (ref == null) return;
    await ref.set({
      'dismissedPaymentHistoryNotices': FieldValue.arrayUnion([trimmed]),
    }, SetOptions(merge: true));
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
                  color: _accentGold.withValues(alpha: 0.9),
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
                tabs: [
                  const Tab(text: 'Payout Account'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('History'),
                        const SizedBox(width: 6),
                        StreamBuilder<int>(
                          stream:
                              _activeTargetRef == null ||
                                  (FirebaseAuth.instance.currentUser?.uid ?? '')
                                      .isEmpty
                              ? Stream<int>.empty()
                              : _newPaymentHistoryCountStream(
                                  userId:
                                      FirebaseAuth.instance.currentUser!.uid,
                                  targetRef: _activeTargetRef!,
                                ),
                          builder: (context, snapshot) {
                            final count = snapshot.data ?? 0;
                            if (count <= 0) return const SizedBox.shrink();
                            return _CountPill(count: count);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  _buildBankDropdownField(),
                  const SizedBox(height: 14),
                  _buildPayoutField('Account Holder', _accountNameController),
                  const SizedBox(height: 12),
                  _buildPayoutField(
                    'Account Number',
                    _accountNumberController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSave ? _savePaymentDetails : null,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return _hasChanges
                        ? _accentGold.withValues(alpha: 204)
                        : Colors.grey.shade300;
                  }
                  return _accentGold;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return _hasChanges ? Colors.white : Colors.grey.shade600;
                  }
                  return Colors.black;
                }),
                elevation: WidgetStateProperty.resolveWith<double>((states) {
                  if (states.contains(WidgetState.disabled)) return 0;
                  return 2;
                }),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 14),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _canSave => _hasChanges && !_isSaving && _isFormValid;

  void _onFormFieldChanged() {
    final valid =
        (_selectedBank?.trim().isNotEmpty ?? false) &&
        _accountNameController.text.trim().isNotEmpty &&
        _accountNumberController.text.trim().isNotEmpty;
    final dirty =
        (_selectedBank?.trim() ?? '') != _initialBankName ||
        _accountNameController.text.trim() != _initialAccountName ||
        _accountNumberController.text.trim() != _initialAccountNumber;
    if (valid != _isFormValid || dirty != _hasChanges) {
      setState(() {
        _isFormValid = valid;
        _hasChanges = dirty;
      });
    }
  }

  List<String> get _filteredBanks {
    final query = _bankSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _malaysiaBanks;
    return _malaysiaBanks
        .where((bank) => bank.toLowerCase().contains(query))
        .toList();
  }

  void _refreshBankOverlay() {
    _bankOverlayEntry?.markNeedsBuild();
  }

  void _toggleBankMenu() {
    if (_bankOverlayEntry != null) {
      _closeBankMenu();
    } else {
      _showBankMenu();
    }
  }

  void _showBankMenu() {
    _bankSearchController.text = '';
    final overlay = Overlay.of(context);
    final renderBox =
        _bankFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    _bankOverlayEntry = OverlayEntry(
      builder: (context) {
        final banks = _filteredBanks;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeBankMenu,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 6,
              width: size.width,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: SizedBox(
                          width: size.width - 24,
                          child: TextField(
                            focusNode: _bankSearchFocusNode,
                            controller: _bankSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search bank',
                              hintStyle: const TextStyle(color: Colors.black45),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.black45,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.black87,
                                  width: 1.2,
                                ),
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: banks.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No banks found'),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: banks.length,
                                shrinkWrap: true,
                                itemBuilder: (context, index) {
                                  final bank = banks[index];
                                  return InkWell(
                                    onTap: () => _selectBank(bank),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Text(
                                        bank,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _profileDarkText,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_bankOverlayEntry!);
    Future.delayed(Duration.zero, () => _bankSearchFocusNode.requestFocus());
  }

  void _closeBankMenu() {
    _bankOverlayEntry?.remove();
    _bankOverlayEntry = null;
  }

  void _selectBank(String bank) {
    setState(() {
      _selectedBank = bank;
      _bankFieldController.text = bank;
    });
    _onFormFieldChanged();
    _closeBankMenu();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          "Discard changes?",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          "You have unsaved changes. Leave anyway?",
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    "Cancel",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF4B63D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Discard",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) {
      Navigator.of(context).pop();
    }
    return false;
  }

  Widget _buildBankDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bank Name',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _bankFieldLink,
          child: TextFormField(
            key: _bankFieldKey,
            controller: _bankFieldController,
            readOnly: true,
            onTap: _toggleBankMenu,
            decoration: InputDecoration(
              hintText: 'Select a bank',
              hintStyle: const TextStyle(color: Colors.black38),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.expand_more, color: Colors.black38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _profileDarkText,
            ),
            validator: (_) => (_selectedBank?.isNotEmpty ?? false)
                ? null
                : 'Please select a bank',
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter $label';
            }
            return null;
          },
          inputFormatters: inputFormatters,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
          decoration: InputDecoration(
            hintText: 'Enter $label',
            hintStyle: _payoutHintStyle,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _profileDarkText, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _historySection() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();
    final paymentField = _isCaregiverPov ? 'booking.caregiverId' : 'userId';
    final baseQuery = FirebaseFirestore.instance
        .collection('payments')
        .where(paymentField, isEqualTo: userId);
    // Avoid `orderBy(updatedAt)` here because some legacy docs may have missing
    // or mixed-type `updatedAt`, which can break the query. We sort locally.
    final stream = baseQuery.snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        bool isCaregiverVisible(Map<String, dynamic> data) {
          if (!_isCaregiverPov) return true;
          final status = (data['status'] as num?)?.toInt();
          final paymentStatus =
              (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? '';
          final bookingStatus =
              (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
          final isPaid =
              status == 1 ||
              paymentStatus == 'PAID' ||
              paymentStatus == 'SUCCESS';
          final isCancelled =
              bookingStatus.contains('CANCEL') ||
              paymentStatus == 'CANCELLED' ||
              paymentStatus == 'CANCELED' ||
              paymentStatus == 'REFUND_REQUESTED' ||
              paymentStatus == 'REFUNDED';
          return isPaid || isCancelled;
        }

        if (snapshot.hasError) {
          return _historyPlaceholder(
            'Unable to load payments.',
            'Please check your connection and try again.\n${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final snap = snapshot.data;
        final docs = snap?.docs ?? const [];
        if (snap != null && !snap.metadata.isFromCache) {
          // Avoid brief "flash then disappear" when the first server snapshot is
          // temporarily empty due to latency/rules propagation. Only overwrite
          // the server cache when we actually receive documents.
          if (docs.isNotEmpty) {
            _paymentDocsFromServer = docs;
          }
          _hasSeenPaymentServerSnapshot = true;
        }

        // Prevent showing stale local-cache payments that may have been deleted
        // or updated in Firestore. Prefer server-backed snapshots.
        final effectiveDocs = _hasSeenPaymentServerSnapshot
            ? _paymentDocsFromServer
            : docs;

        // Avoid infinite loading when Firestore stays on cache-only snapshots
        // (e.g. slow network/rules/index propagation). If cache has docs, show
        // them immediately. If cache is empty, show a loader briefly, then show
        // the empty state.
        final isCacheOnly = snap?.metadata.isFromCache == true;
        if (!_hasSeenPaymentServerSnapshot && isCacheOnly) {
          _paymentsCacheFirstSeenAt ??= DateTime.now();
          final elapsed = DateTime.now().difference(_paymentsCacheFirstSeenAt!);
          if (docs.isEmpty && elapsed < const Duration(seconds: 2)) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!mounted) return;
              setState(() {});
            });
            return const Center(child: CircularProgressIndicator());
          }
        } else {
          _paymentsCacheFirstSeenAt = null;
        }

        final sortedDocs =
            List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(effectiveDocs)
              ..sort((a, b) {
                final tsA = a.data()['updatedAt'] as Timestamp?;
                final tsB = b.data()['updatedAt'] as Timestamp?;
                if (tsA == null && tsB == null) return 0;
                if (tsA == null) return 1;
                if (tsB == null) return -1;
                return tsB.compareTo(tsA);
              });

        final visibleDocs = sortedDocs.where((doc) {
          if (_hiddenPaymentIds.contains(doc.id)) return false;
          final data = doc.data();
          if (_isPaymentHiddenForUser(data, userId)) return false;
          if (!isCaregiverVisible(data)) return false;
          final status = (data['status'] as num?)?.toInt();
          final paymentStatus = (data['paymentStatus'] as String?)
              ?.trim()
              .toUpperCase();
          return !(status == 3 || paymentStatus == 'FAILED');
        }).toList();

        if (!_isCaregiverPov &&
            _hasSeenPaymentServerSnapshot &&
            visibleDocs.isEmpty) {
          _legacyPaymentsByBookingFuture ??= _loadLegacyPaymentsByBookingId(
            userId,
          );
          return FutureBuilder<
            List<QueryDocumentSnapshot<Map<String, dynamic>>>
          >(
            future: _legacyPaymentsByBookingFuture,
            builder: (context, legacySnapshot) {
              if (legacySnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final legacyDocs = legacySnapshot.data ?? const [];
              final merged =
                  legacyDocs.where((doc) {
                    if (_hiddenPaymentIds.contains(doc.id)) return false;
                    final data = doc.data();
                    if (_isPaymentHiddenForUser(data, userId)) return false;
                    final status = (data['status'] as num?)?.toInt();
                    final paymentStatus = (data['paymentStatus'] as String?)
                        ?.trim()
                        .toUpperCase();
                    return !(status == 3 || paymentStatus == 'FAILED');
                  }).toList()..sort((a, b) {
                    final tsA = a.data()['updatedAt'] as Timestamp?;
                    final tsB = b.data()['updatedAt'] as Timestamp?;
                    if (tsA == null && tsB == null) return 0;
                    if (tsA == null) return 1;
                    if (tsB == null) return -1;
                    return tsB.compareTo(tsA);
                  });

              if (merged.isEmpty) {
                return _historyPlaceholder(
                  'No payment history yet.',
                  'Pending and completed payments will appear here.',
                );
              }
              return _buildHistoryList(merged, const [], const []);
            },
          );
        }

        final notices = <_HistoryNoticeCard>[];
        final pendingMessage = _historyNotificationMessage?.trim() ?? '';
        if (!_isCaregiverPov &&
            pendingMessage.isNotEmpty &&
            !_dismissedPaymentNotices.contains(pendingMessage)) {
          notices.add(
            _HistoryNoticeCard(
              message: pendingMessage,
              statusLabel: 'Pending',
              onDelete: () => _dismissPendingPaymentNotice(pendingMessage),
            ),
          );
        }

        final withdrawStream = _isCaregiverPov
            ? FirebaseFirestore.instance
                  .collection('withdrawRequests')
                  .where('caregiverId', isEqualTo: userId)
                  // Avoid composite-index / mixed-type issues on `requestedAt`.
                  // We sort locally instead.
                  .snapshots()
            : null;
        if (withdrawStream == null) {
          if (visibleDocs.isEmpty && notices.isEmpty) {
            return _historyPlaceholder(
              'No payment history yet.',
              'Pending and completed payments will appear here.',
            );
          }
          return _buildHistoryList(visibleDocs, notices, const []);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: withdrawStream,
          builder: (context, withdrawSnapshot) {
            if (withdrawSnapshot.hasError) {
              if (visibleDocs.isEmpty && notices.isEmpty) {
                return _historyPlaceholder(
                  'Unable to load withdrawals.',
                  'Please check your connection and try again.',
                );
              }
              return _buildHistoryList(visibleDocs, notices, const []);
            }

            final withdrawData = withdrawSnapshot.data;
            if (withdrawData != null && !withdrawData.metadata.isFromCache) {
              _withdrawDocsFromServer = List.of(withdrawData.docs)
                ..sort((a, b) {
                  final aTs = a.data()['requestedAt'] as Timestamp?;
                  final bTs = b.data()['requestedAt'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });
              _hasSeenWithdrawServerSnapshot = true;
            }

            // Avoid showing stale local-cache results (can briefly show deleted
            // requests). Prefer the first server-backed snapshot instead.
            final effectiveWithdrawDocs = _hasSeenWithdrawServerSnapshot
                ? _withdrawDocsFromServer
                : (withdrawData?.metadata.isFromCache == true
                      ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                      : (List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(
                          withdrawData?.docs ??
                              const <
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >[],
                        )..sort((a, b) {
                          final aTs = a.data()['requestedAt'] as Timestamp?;
                          final bTs = b.data()['requestedAt'] as Timestamp?;
                          if (aTs == null && bTs == null) return 0;
                          if (aTs == null) return 1;
                          if (bTs == null) return -1;
                          return bTs.compareTo(aTs);
                        })));
            if (visibleDocs.isEmpty &&
                effectiveWithdrawDocs.isEmpty &&
                notices.isEmpty) {
              return _historyPlaceholder(
                'No payment history yet.',
                'Pending and completed payments will appear here.',
              );
            }
            return _buildHistoryList(
              visibleDocs,
              notices,
              effectiveWithdrawDocs,
            );
          },
        );
      },
    );
  }

  Widget _historyPlaceholder(String headline, String explanation) {
    return _buildEmptyReminder(
      icon: Icons.receipt_long_outlined,
      headline: headline,
      explanation: explanation,
      iconColor: _reminderIconColor,
    );
  }

  Widget _buildHistoryList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleDocs,
    List<_HistoryNoticeCard> notices,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> withdrawDocs,
  ) {
    final entries = <Widget>[];
    if (notices.isNotEmpty) {
      entries.addAll(notices);
    }

    final lastSeen = _lastSeenPaymentHistoryAt;
    for (final doc in withdrawDocs) {
      entries.add(_buildWithdrawHistoryCard(doc));
    }
    for (final doc in visibleDocs) {
      if (_isCancelledOrRefundPayment(doc.data())) {
        entries.add(_buildCancelRefundNoticeCard(doc));
        continue;
      }
      final updatedAt = doc.data()['updatedAt'] as Timestamp?;
      final isNew =
          lastSeen != null &&
          updatedAt != null &&
          updatedAt.compareTo(lastSeen) > 0;
      entries.add(_paymentHistoryCard(doc.id, doc.data(), isNew: isNew));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => entries[index],
    );
  }

  Widget _buildWithdrawHistoryCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
    final normalized = ((data['status'] as String?) ?? 'pending')
        .trim()
        .toLowerCase();
    final verified = data['verified'] == true;
    final receiptUrl = ((data['receiptUrl'] as String?) ?? '').trim();
    final receiptFileName =
        ((data['receiptFileName'] as String?) ?? '').trim().isNotEmpty
        ? ((data['receiptFileName'] as String?) ?? '').trim()
        : 'withdraw-receipt-${doc.id}.pdf';
    final iconColor = switch (normalized) {
      'approved' => _statusPaid,
      'rejected' => _statusCancelled,
      'failed' => _statusCancelled,
      _ => _accentGold,
    };
    return _HistoryNoticeCard(
      icon: Icons.account_balance_wallet_outlined,
      iconColor: iconColor,
      statusLabel: _withdrawStatusLabel(data),
      message: _withdrawRequestMessage(data),
      requestedAt: requestedAt,
      footer: verified && receiptUrl.isNotEmpty
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _downloadWithdrawReceiptPdf(
                  url: receiptUrl,
                  fileName: receiptFileName,
                  feedbackContext: context,
                ),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text(
                  'Download receipt',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  bool _isCancelledOrRefundPayment(Map<String, dynamic> data) {
    final bookingStatus =
        (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
    final paymentStatus =
        (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? '';
    return bookingStatus.contains('CANCEL') ||
        paymentStatus == 'CANCELLED' ||
        paymentStatus == 'CANCELED' ||
        paymentStatus.startsWith('REFUND');
  }

  String _refundNoticeStatusLabel({
    required String bookingStatus,
    required String paymentStatus,
    required bool verified,
  }) {
    if (verified) return 'Refund verified';
    if (paymentStatus == 'REFUNDED') return 'Refund verified';
    if (paymentStatus == 'REFUND_REQUESTED')
      return 'Refund verification pending';
    if (bookingStatus.contains('CANCEL')) return 'Refund verification pending';
    if (paymentStatus == 'CANCELLED' || paymentStatus == 'CANCELED') {
      return 'Cancelled';
    }
    return 'Refund verification pending';
  }

  String _refundNoticeMessage(Map<String, dynamic> data) {
    final booking =
        (data['booking'] as Map?)?.cast<String, dynamic>() ?? const {};
    final caregiverName =
        (booking['caregiverName'] as String?)?.trim() ??
        (data['caregiverName'] as String?)?.trim() ??
        '';
    final personName =
        (booking['personName'] as String?)?.trim() ??
        (data['personName'] as String?)?.trim() ??
        '';
    final date =
        (booking['date'] as String?)?.trim() ??
        (data['date'] as String?)?.trim() ??
        '';
    final time =
        (booking['time'] as String?)?.trim() ??
        (data['time'] as String?)?.trim() ??
        '';
    final amount =
        (data['amount'] as num?)?.toDouble() ??
        (booking['servicePrice'] as num?)?.toDouble() ??
        0.0;

    final bookingLineParts = <String>[
      if (caregiverName.isNotEmpty) caregiverName,
      if (personName.isNotEmpty) personName,
    ];
    final bookingLine = bookingLineParts.isEmpty
        ? ''
        : 'Booking: ${bookingLineParts.join(' • ')}';

    final scheduleParts = <String>[
      if (date.isNotEmpty) date,
      if (time.isNotEmpty) time,
    ];
    final scheduleLine = scheduleParts.isEmpty
        ? ''
        : 'Schedule: ${scheduleParts.join(' • ')}';

    final lines = <String>[
      (data['verified'] == true)
          ? 'Refund verified.'
          : 'Booking cancelled. Refund verification pending.',
      if (bookingLine.isNotEmpty) bookingLine,
      if (scheduleLine.isNotEmpty) scheduleLine,
      'Amount: ${_toCurrency(amount)}',
    ];
    return lines.join('\n');
  }

  Widget _buildCancelRefundNoticeCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final bookingStatus =
        (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
    final paymentStatus =
        (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? '';
    final verified = data['verified'] == true;
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();

    final statusLabel = _refundNoticeStatusLabel(
      bookingStatus: bookingStatus,
      paymentStatus: paymentStatus,
      verified: verified,
    );
    final iconColor = verified || paymentStatus == 'REFUNDED'
        ? _statusPaid
        : _accentGold;

    return _HistoryNoticeCard(
      icon: Icons.assignment_return_outlined,
      iconColor: iconColor,
      statusLabel: statusLabel,
      message: _refundNoticeMessage(data),
      requestedAt: updatedAt,
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () =>
              _openPaymentReceiptSheet(paymentId: doc.id, payment: data),
          icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
          label: const Text(
            'View details',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentGold,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  String _withdrawStatusLabel(Map<String, dynamic> data) {
    final rawStatus = (data['status'] as String?) ?? 'pending';
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'approved':
        return 'Approved';
      case 'rejected':
      case 'failed':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  String _withdrawRequestMessage(Map<String, dynamic> data) {
    final rawStatus = (data['status'] as String?) ?? 'pending';
    final normalized = rawStatus.trim().toLowerCase();
    final requested = _toCurrency(
      _readMoney(data['thisWeekAmount']) > 0
          ? _readMoney(data['thisWeekAmount'])
          : _readMoney(data['payoutAmount']),
    );
    final approved = _toCurrency(
      _readMoney(data['approvedAmount']) > 0
          ? _readMoney(data['approvedAmount'])
          : (_readMoney(data['payoutAmount']) > 0
                ? _readMoney(data['payoutAmount'])
                : _readMoney(data['thisWeekAmount'])),
    );
    switch (normalized) {
      case 'approved':
        return 'Withdraw request approved.\nRequested: $requested\nApproved: $approved';
      case 'rejected':
      case 'failed':
        return 'Withdraw request declined.\nRequested: $requested';
      default:
        return 'Withdraw request sent.\nRequested: $requested\nPlease allow up to 24 hours for admin verification.';
    }
  }

  String _toCurrency(double value) {
    if (value <= 0) return 'RM 0.00';
    return 'RM ${_formatMoney(value)}';
  }

  Future<void> _downloadWithdrawReceiptPdf({
    required String url,
    required String fileName,
    required BuildContext feedbackContext,
  }) async {
    if (kIsWeb) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Download unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Download is not available on web.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (!(Platform.isAndroid || Platform.isIOS || Platform.isFuchsia)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Download unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Download is not available on this platform.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

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
      useRootNavigator: true,
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
                    'Downloading receipt...',
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
      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw Exception('Invalid URL');
      }
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to download (${response.statusCode})');
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        throw Exception('Empty file');
      }

      final dir = await getApplicationDocumentsDirectory();
      final safeName = fileName.trim().isNotEmpty
          ? fileName.trim()
          : 'withdraw-receipt.pdf';
      final path = '${dir.path}/$safeName';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      closeLoadingIfOpen();

      await OpenFilex.open(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        feedbackContext,
      ).showSnackBar(const SnackBar(content: Text('Receipt downloaded.')));
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Unable to download receipt',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      closeLoadingIfOpen();
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _determineTargetRef(
    String userId,
  ) async {
    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(userId);
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    switch (widget.target) {
      case PaymentDocumentTarget.caregiver:
        return caregiverRef;
      case PaymentDocumentTarget.user:
        return userRef;
      case PaymentDocumentTarget.auto:
        final caregiverSnap = await caregiverRef.get();
        if (caregiverSnap.exists) return caregiverRef;
        return userRef;
    }
  }

  // ignore: unused_element
  Widget _historyCard(
    String id,
    Map<String, dynamic> data, {
    bool isNew = false,
  }) {
    final serviceLabel = extractServiceLabelFromFirestore(data);
    final service = serviceLabel.isNotEmpty ? serviceLabel : 'Service';
    final amount = (data['servicePrice'] as num?)?.toDouble() ?? 0;
    final bookingStatus =
        (data['status'] as String?)?.toUpperCase() ?? 'PENDING';
    final paymentStatus =
        (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? '';
    final reason = (data['cancellationReason'] as String?) ?? '';
    final personName = (data['personName'] as String?) ?? '';
    final caregiverName = (data['caregiverName'] as String?) ?? '';
    final personAddress = (data['personAddress'] as String?) ?? '';
    final date = (data['date'] as String?) ?? '';
    final time = (data['time'] as String?) ?? '';
    final notes =
        (data['personNotes'] as String?) ?? (data['notes'] as String?) ?? '';
    final showRefundInProgress =
        bookingStatus.contains('CANCEL') || paymentStatus.startsWith('REFUND');
    final String? refundStatusLabel = () {
      if (paymentStatus == 'REFUNDED') return 'Refund verified';
      if (paymentStatus == 'REFUND_REQUESTED')
        return 'Refund verification pending';
      if (bookingStatus.contains('CANCEL'))
        return 'Refund verification pending';
      return null;
    }();

    return _SwipeableHistoryCard(
      backgroundBuilder: (onDeleteTap) => _buildDeleteBackground(onDeleteTap),
      onDeletePressed: () => _confirmHideBooking(id),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: _historyCardBorderRadius,
          child: Container(
            padding: const EdgeInsets.all(14),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusChip(bookingStatus: bookingStatus),
                        const SizedBox(height: 6),
                        if (isNew) const _CountPill(count: 1),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      size: 12,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      date.isNotEmpty ? date : '-',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time.isNotEmpty ? time : '-',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName.isNotEmpty
                                  ? personName
                                  : caregiverName,
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                    const Spacer(),
                    if (showRefundInProgress)
                      Text(
                        refundStatusLabel ?? 'Refund verification pending',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      notes,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentHistoryCard(
    String id,
    Map<String, dynamic> data, {
    bool isNew = false,
  }) {
    final booking =
        (data['booking'] as Map?)?.cast<String, dynamic>() ?? const {};
    final caregiverName =
        (booking['caregiverName'] as String?)?.trim() ?? 'Caregiver';
    final caregiverPhoto = (booking['caregiverPhoto'] as String?)?.trim();
    final personName = (booking['personName'] as String?)?.trim() ?? '';
    final date = (booking['date'] as String?)?.trim() ?? '';
    final time = (booking['time'] as String?)?.trim() ?? '';
    final serviceLabel = extractServiceLabelFromFirestore(booking);
    final service = serviceLabel.isNotEmpty
        ? serviceLabel
        : (booking['service'] as String?)?.trim() ?? 'Service';
    final amount =
        (data['amount'] as num?)?.toDouble() ??
        (booking['servicePrice'] as num?)?.toDouble() ??
        0.0;
    const serviceFee = 1.0;
    final afterServiceFee = (amount - serviceFee).clamp(0.0, double.infinity);
    final platformFee = (afterServiceFee * 0.07).clamp(0.0, double.infinity);
    final netAmount = (afterServiceFee - platformFee).clamp(
      0.0,
      double.infinity,
    );
    final displayedAmount = _isCaregiverPov ? netAmount : amount;
    final paymentStatus =
        (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? 'PENDING';
    final bookingStatus =
        (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
    final bool showRefundNotice =
        !_isCaregiverPov &&
        (paymentStatus == 'REFUND_REQUESTED' ||
            paymentStatus == 'REFUNDED' ||
            bookingStatus.contains('CANCEL'));
    final String? refundNoticeLabel = () {
      if (paymentStatus == 'REFUNDED') return 'Refund verified';
      if (paymentStatus == 'REFUND_REQUESTED')
        return 'Refund verification pending';
      if (bookingStatus.contains('CANCEL'))
        return 'Refund verification pending';
      return null;
    }();

    return _SwipeableHistoryCard(
      backgroundBuilder: (onDeleteTap) => _buildDeleteBackground(onDeleteTap),
      onDeletePressed: () => _confirmHidePayment(id),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPaymentReceiptSheet(paymentId: id, payment: data),
          borderRadius: _historyCardBorderRadius,
          child: Container(
            padding: const EdgeInsets.all(14),
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
                    DefaultProfileAvatar(
                      radius: 18,
                      photoUrl: caregiverPhoto?.isNotEmpty == true
                          ? caregiverPhoto
                          : null,
                      label: caregiverName.isNotEmpty ? caregiverName : '?',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  caregiverName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _profileDarkText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (bookingStatus.isNotEmpty)
                                _StatusChip(bookingStatus: bookingStatus),
                            ],
                          ),
                          if (service.isNotEmpty)
                            Text(
                              service,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [if (isNew) const _CountPill(count: 1)],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      'RM ${displayedAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _profileDarkText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PaymentStatusChip(paymentStatus: paymentStatus),
                    const Spacer(),
                    // booking status shown in the top chip
                  ],
                ),
                if (showRefundNotice && refundNoticeLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    refundNoticeLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [date, time].where((v) => v.isNotEmpty).join(' • '),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (personName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          personName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatMoney(double value) => value.toStringAsFixed(2);

  double _readMoney(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
    return 0.0;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Iterable) {
      final joinable = value.whereType<String>().toList();
      if (joinable.isNotEmpty) return joinable.join(', ');
    }
    if (value != null) return value.toString();
    return null;
  }

  static const TextStyle _receiptSectionHeaderTextStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: _profileDarkText,
    letterSpacing: -0.15,
  );

  static const TextStyle _receiptFieldLabelTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: _receiptMutedText,
  );

  static const TextStyle _receiptFieldValueTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: _profileDarkText,
    height: 1.25,
  );

  BoxDecoration _receiptPremiumCardDecoration({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _receiptCardBorderStrong),
      boxShadow: const [
        BoxShadow(
          color: _receiptCardShadow,
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  Widget _receiptSectionHeader({required String title, String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: _receiptSectionHeaderTextStyle),
              ),
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

  Widget _receiptTabContent(List<Widget> children) {
    return Container(
      decoration: _receiptPremiumCardDecoration(),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }

  Widget _receiptInfoRow({
    required IconData icon,
    required String title,
    required String value,
    bool showBorder = true,
  }) {
    final display = value.trim().isNotEmpty ? value.trim() : 'Unavailable';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? BorderSide(color: Colors.black.withValues(alpha: 0.06))
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _reminderIconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _receiptFieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(display, style: _receiptFieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _loadBookingSummaryForPayment({
    required String paymentId,
    required Map<String, dynamic> payment,
  }) async {
    final booking =
        (payment['booking'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final bookingId =
        (payment['bookingId'] as String?)?.trim() ??
        (booking['bookingId'] as String?)?.trim() ??
        '';
    final ownerUserId =
        (payment['userId'] as String?)?.trim() ??
        (booking['userId'] as String?)?.trim() ??
        '';
    var resolvedBooking = Map<String, dynamic>.from(booking);
    if (bookingId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();
      if (snap.exists) {
        resolvedBooking = {...resolvedBooking, ...?snap.data()};
      }
    }

    String? ownerName;
    String? ownerPhone;
    if (ownerUserId.isNotEmpty) {
      try {
        final ownerSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerUserId)
            .get();
        final data = ownerSnap.data();
        if (data != null) {
          final personId =
              (resolvedBooking['personId'] as String?)?.trim() ?? '';
          final addressId =
              (resolvedBooking['addressId'] as String?)?.trim() ?? '';
          final entries =
              (data['address'] as List?)?.whereType<Map>().toList() ?? const [];
          Map? selectedEntry;
          if (personId.trim().isNotEmpty) {
            for (final entry in entries) {
              final entryId =
                  entry['id']?.toString() ?? entry['personId']?.toString();
              if (entryId != null && entryId == personId.trim()) {
                selectedEntry = entry;
                break;
              }
            }
          }
          if (selectedEntry == null && bookingId.trim().isNotEmpty) {
            for (final entry in entries) {
              final entryBookingId = entry['bookingId']?.toString();
              if (entryBookingId != null &&
                  entryBookingId == bookingId.trim()) {
                selectedEntry = entry;
                break;
              }
            }
          }
          if (selectedEntry == null && addressId.trim().isNotEmpty) {
            for (final entry in entries) {
              final entryAddressId = entry['addressId']?.toString();
              if (entryAddressId != null &&
                  entryAddressId == addressId.trim()) {
                selectedEntry = entry;
                break;
              }
            }
          }

          ownerName = (data['name'] as String?)?.trim();
          ownerPhone =
              (data['phone'] as String?)?.trim() ??
              (data['phoneNumber'] as String?)?.trim();

          // Match ActivityBookingDetailsScreen: prefer selected address entry phone.
          if (selectedEntry != null) {
            final pickedPhone = _stringValue(selectedEntry['phone']);
            if (pickedPhone != null) {
              resolvedBooking['personPhone'] = pickedPhone;
            }
          }
        }
      } catch (_) {}
    }

    final caregiverId =
        (resolvedBooking['caregiverId'] as String?)?.trim() ??
        (payment['caregiverId'] as String?)?.trim() ??
        '';
    String? caregiverPhone;
    if (caregiverId.isNotEmpty) {
      try {
        final caregiverSnap = await FirebaseFirestore.instance
            .collection('caregivers')
            .doc(caregiverId)
            .get();
        final data = caregiverSnap.data();
        if (data != null) {
          caregiverPhone =
              (data['phone'] as String?)?.trim() ??
              (data['phoneNumber'] as String?)?.trim();
        }
      } catch (_) {}
    }

    final personPhone =
        _stringValue(resolvedBooking['personPhone']) ??
        _stringValue(resolvedBooking['phone']) ??
        _stringValue(resolvedBooking['personContact']) ??
        _stringValue(resolvedBooking['personNumber']) ??
        '';

    final paymentStatus =
        (payment['paymentStatus'] as String?)?.trim().toUpperCase() ??
        'PENDING';
    final bookingStatus =
        (payment['bookingStatus'] as String?)?.trim().toUpperCase() ??
        (resolvedBooking['status'] as String?)?.trim().toUpperCase() ??
        '';
    final paidAt = payment['paidAt'] ?? resolvedBooking['paidAt'];
    final updatedAt = payment['updatedAt'] ?? resolvedBooking['updatedAt'];
    final servicePrice = _readMoney(resolvedBooking['servicePrice']);
    final distanceKm = _readMoney(resolvedBooking['distanceKm']);
    final distanceCharge = _readMoney(resolvedBooking['distanceCharge']);
    final amount = _readMoney(payment['amount']);
    final total = amount > 0 ? amount : (servicePrice + distanceCharge);

    return {
      'paymentId': paymentId,
      'bookingId': bookingId,
      'billCode': (payment['billCode'] as String?)?.trim() ?? '',
      'paymentUrl': (payment['paymentUrl'] as String?)?.trim() ?? '',
      'paymentStatus': paymentStatus,
      'bookingStatus': bookingStatus,
      'paidAt': paidAt,
      'updatedAt': updatedAt,
      'paymentMethod':
          (payment['paymentMethod'] as String?)?.trim() ??
          (resolvedBooking['paymentMethod'] as String?)?.trim() ??
          'ToyyibPay',
      'amount': total,
      'servicePrice': servicePrice,
      'distanceKm': distanceKm,
      'distanceCharge': distanceCharge,
      'caregiverId': caregiverId,
      'caregiverName':
          (resolvedBooking['caregiverName'] as String?)?.trim() ?? '',
      'caregiverPhoto':
          (resolvedBooking['caregiverPhoto'] as String?)?.trim() ?? '',
      'caregiverPhone':
          (resolvedBooking['caregiverPhone'] as String?)?.trim() ??
          (resolvedBooking['caregiverContact'] as String?)?.trim() ??
          caregiverPhone ??
          '',
      'service':
          extractServiceLabelFromFirestore(resolvedBooking).trim().isNotEmpty
          ? extractServiceLabelFromFirestore(resolvedBooking).trim()
          : (resolvedBooking['service'] as String?)?.trim() ?? 'Service',
      'date': (resolvedBooking['date'] as String?)?.trim() ?? '',
      'time': (resolvedBooking['time'] as String?)?.trim() ?? '',
      'startTime': (resolvedBooking['startTime'] as String?)?.trim() ?? '',
      'endTime': (resolvedBooking['endTime'] as String?)?.trim() ?? '',
      'personId': (resolvedBooking['personId'] as String?)?.trim() ?? '',
      'personName': (resolvedBooking['personName'] as String?)?.trim() ?? '',
      'personAddress':
          (resolvedBooking['personAddress'] as String?)?.trim() ?? '',
      'personPhone': personPhone,
      'personPhotoUrl':
          (resolvedBooking['personPhotoUrl'] as String?)?.trim() ??
          (resolvedBooking['personPhoto'] as String?)?.trim() ??
          (resolvedBooking['personAvatarUrl'] as String?)?.trim() ??
          (resolvedBooking['personImageUrl'] as String?)?.trim() ??
          '',
      'personNotes':
          (resolvedBooking['personNotes'] as String?) ??
          (resolvedBooking['notes'] as String?) ??
          '',
      'bookingNotes':
          (resolvedBooking['bookingNotes'] as String?)?.trim() ?? '',
      'ownerName':
          (resolvedBooking['ownerName'] as String?)?.trim() ??
          (resolvedBooking['bookedBy'] as String?)?.trim() ??
          ownerName ??
          '',
      'ownerPhone':
          (resolvedBooking['ownerPhone'] as String?)?.trim() ??
          ownerPhone ??
          '',
    };
  }

  Future<({String fileName, Uint8List bytes})> _generateReceiptPdf({
    required String paymentId,
  }) async {
    final callable = _functions.httpsCallable(
      'generatePaymentReceiptPdf',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final result = await callable
        .call(<String, dynamic>{'paymentId': paymentId})
        .timeout(const Duration(seconds: 75));
    final map = Map<String, dynamic>.from(result.data as Map);
    final pdfBase64 = (map['pdfBase64'] as String?) ?? '';
    final fileName = (map['fileName'] as String?) ?? 'payment-receipt.pdf';
    if (pdfBase64.trim().isEmpty) {
      throw Exception('Missing pdfBase64');
    }
    return (fileName: fileName, bytes: base64Decode(pdfBase64));
  }

  Future<({String url, String fileName})?> _adminUploadedReceiptForPayment(
    String paymentId,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .doc(paymentId)
          .get();
      final data = snap.data();
      if (data == null) return null;
      final url = (data['receiptUrl'] as String?)?.trim() ?? '';
      if (url.isEmpty) return null;
      final name = ((data['receiptFileName'] as String?) ?? '').trim();
      final fileName = name.isNotEmpty
          ? name
          : 'payment-receipt-$paymentId.pdf';
      return (url: url, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadReceiptPdf(
    String paymentId,
    BuildContext feedbackContext,
  ) async {
    if (kIsWeb) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Download unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Download is not available on web.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isFuchsia)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Download unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Download is not available on this platform.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

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
      useRootNavigator: true,
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
                    'Preparing receipt…',
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
      final adminReceipt = await _adminUploadedReceiptForPayment(paymentId);
      final ({String fileName, Uint8List bytes}) generated;
      if (adminReceipt != null) {
        final uri = Uri.tryParse(adminReceipt.url);
        if (uri == null) throw Exception('Invalid receipt URL');
        final response = await http.get(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Failed to download (${response.statusCode})');
        }
        final bytes = response.bodyBytes;
        if (bytes.isEmpty) throw Exception('Empty file');
        generated = (fileName: adminReceipt.fileName, bytes: bytes);
      } else {
        generated = await _generateReceiptPdf(paymentId: paymentId);
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${generated.fileName}';
      final file = File(path);
      await file.writeAsBytes(generated.bytes, flush: true);
      closeLoadingIfOpen();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Receipt saved',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            generated.fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Unable to download receipt',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _shareReceiptPdf(
    String paymentId,
    BuildContext feedbackContext,
  ) async {
    if (kIsWeb) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Share unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Share is not available on web.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isFuchsia)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Share unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Share is not available on this platform.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

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
      useRootNavigator: true,
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
                    'Preparing receipt…',
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
      final adminReceipt = await _adminUploadedReceiptForPayment(paymentId);
      final ({String fileName, Uint8List bytes}) generated;
      if (adminReceipt != null) {
        final uri = Uri.tryParse(adminReceipt.url);
        if (uri == null) throw Exception('Invalid receipt URL');
        final response = await http.get(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Failed to download (${response.statusCode})');
        }
        final bytes = response.bodyBytes;
        if (bytes.isEmpty) throw Exception('Empty file');
        generated = (fileName: adminReceipt.fileName, bytes: bytes);
      } else {
        generated = await _generateReceiptPdf(paymentId: paymentId);
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${generated.fileName}';
      final file = File(path);
      await file.writeAsBytes(generated.bytes, flush: true);
      closeLoadingIfOpen();
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(path, mimeType: 'application/pdf', name: generated.fileName),
      ], subject: generated.fileName);
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Unable to share receipt',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openPaymentReceiptSheet({
    required String paymentId,
    required Map<String, dynamic> payment,
  }) async {
    final future = _loadBookingSummaryForPayment(
      paymentId: paymentId,
      payment: payment,
    );
    final normalizedPaymentStatus =
        (payment['paymentStatus'] as String?)?.trim().toUpperCase() ??
        'PENDING';
    final normalizedBookingStatus =
        (payment['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';
    final verified = payment['verified'] == true;
    final refundVerified = verified || normalizedPaymentStatus == 'REFUNDED';
    final isRefundFlow =
        normalizedPaymentStatus.startsWith('REFUND') ||
        normalizedBookingStatus.contains('CANCEL');
    final hideReceiptActions =
        normalizedPaymentStatus == 'PENDING' ||
        (isRefundFlow && !refundVerified);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.9;
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _profileDarkText,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close),
                          color: Colors.black54,
                          splashRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              snapshot.error.toString(),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        final d = snapshot.data ?? const <String, dynamic>{};
                        final caregiverName =
                            (d['caregiverName'] as String?)?.trim() ?? '';
                        final caregiverPhone =
                            (d['caregiverPhone'] as String?)?.trim() ?? '';
                        final service =
                            (d['service'] as String?)?.trim() ?? 'Service';
                        final date = (d['date'] as String?)?.trim() ?? '';
                        final time = (d['time'] as String?)?.trim() ?? '';
                        final startTime =
                            (d['startTime'] as String?)?.trim() ?? '';
                        final endTime = (d['endTime'] as String?)?.trim() ?? '';
                        final personName =
                            (d['personName'] as String?)?.trim() ?? '';
                        final personAddress =
                            (d['personAddress'] as String?)?.trim() ?? '';
                        final personPhone =
                            (d['personPhone'] as String?)?.trim() ?? '';
                        final personNotes =
                            (d['personNotes'] as String?)?.trim() ?? '';
                        final bookingNotes =
                            (d['bookingNotes'] as String?)?.trim() ?? '';
                        final paymentStatus =
                            (d['paymentStatus'] as String?)?.trim() ?? '';
                        final bookingStatus =
                            (d['bookingStatus'] as String?)?.trim() ?? '';
                        final paymentMethod =
                            (d['paymentMethod'] as String?)?.trim() ?? '';
                        final ownerName =
                            (d['ownerName'] as String?)?.trim() ?? '';
                        final ownerPhone =
                            (d['ownerPhone'] as String?)?.trim() ?? '';
                        final bookingId =
                            (d['bookingId'] as String?)?.trim() ?? '';
                        final billCode =
                            (d['billCode'] as String?)?.trim() ?? '';
                        final total = _readMoney(d['amount']);
                        final servicePrice = _readMoney(d['servicePrice']);
                        final distanceKm = _readMoney(d['distanceKm']);
                        final distanceCharge = _readMoney(d['distanceCharge']);
                        const serviceFee = 1.0;
                        final afterServiceFee = (total - serviceFee).clamp(
                          0.0,
                          double.infinity,
                        );
                        final platformFee = (afterServiceFee * 0.07).clamp(
                          0.0,
                          double.infinity,
                        );
                        final netTotal = (afterServiceFee - platformFee).clamp(
                          0.0,
                          double.infinity,
                        );
                        final displayedTotal = _isCaregiverPov
                            ? netTotal
                            : total;

                        String scheduleLine() {
                          final parts = <String>[
                            if (date.isNotEmpty) date,
                            if (time.isNotEmpty) time,
                            if (startTime.isNotEmpty && endTime.isNotEmpty)
                              '$startTime - $endTime',
                          ];
                          return parts.join(' • ');
                        }

                        return ScrollConfiguration(
                          behavior: const _NoOverscrollScrollBehavior(),
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    10,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: _cardBorderColor,
                                      ),
                                      boxShadow: [_historyCardShadow],
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                service,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: _profileDarkText,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                caregiverName.isNotEmpty
                                                    ? caregiverName
                                                    : 'Caregiver',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              if (caregiverPhone
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  caregiverPhone,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                              if (scheduleLine()
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  scheduleLine(),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'RM ${_formatMoney(displayedTotal)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w900,
                                                color: _profileDarkText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _receiptSectionHeader(
                                        title: 'Selected person',
                                      ),
                                      _receiptTabContent([
                                        _receiptInfoRow(
                                          icon: Icons.person,
                                          title: 'Name',
                                          value: personName,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.phone_android,
                                          title: 'Contact',
                                          value: personPhone,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.home,
                                          title: 'Location',
                                          value: personAddress,
                                          showBorder: true,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.sticky_note_2_outlined,
                                          title: 'Notes',
                                          value: personNotes.trim(),
                                          showBorder: false,
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _receiptSectionHeader(
                                        title: 'Booking details',
                                      ),
                                      _receiptTabContent([
                                        _receiptInfoRow(
                                          icon: Icons.tag_outlined,
                                          title: 'Booking ID',
                                          value: bookingId,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.medical_services_outlined,
                                          title: 'Services',
                                          value: service,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.schedule_outlined,
                                          title: 'Schedule',
                                          value: scheduleLine(),
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.info_outline,
                                          title: 'Booking status',
                                          value: bookingStatus,
                                          showBorder: true,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.person_outline,
                                          title: 'Booked by',
                                          value: ownerName,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.phone_android,
                                          title: 'Owner contact',
                                          value: ownerPhone,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.notes_outlined,
                                          title: 'Booking notes',
                                          value: bookingNotes.trim(),
                                          showBorder: false,
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _receiptSectionHeader(title: 'Payment'),
                                      _receiptTabContent([
                                        _receiptInfoRow(
                                          icon: Icons.receipt_long_outlined,
                                          title: 'Payment ID',
                                          value: paymentId,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons
                                              .confirmation_number_outlined,
                                          title: 'Bill code',
                                          value: billCode,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.verified_outlined,
                                          title: 'Payment status',
                                          value: paymentStatus,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.payment_outlined,
                                          title: 'Payment method',
                                          value: paymentMethod,
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.attach_money_outlined,
                                          title: 'Service price',
                                          value: servicePrice > 0
                                              ? 'RM ${_formatMoney(servicePrice)}'
                                              : '-',
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.route_outlined,
                                          title: 'Distance',
                                          value: distanceKm > 0
                                              ? '${distanceKm.toStringAsFixed(1)} km'
                                              : '-',
                                        ),
                                        _receiptInfoRow(
                                          icon: Icons.add_road_outlined,
                                          title: 'Distance charge',
                                          value: distanceCharge > 0
                                              ? 'RM ${_formatMoney(distanceCharge)}'
                                              : '-',
                                        ),
                                        if (_isCaregiverPov) ...[
                                          _receiptInfoRow(
                                            icon: Icons.calculate_outlined,
                                            title: 'Total',
                                            value: 'RM ${_formatMoney(total)}',
                                          ),
                                          _receiptInfoRow(
                                            icon: Icons.remove_circle_outline,
                                            title: 'Payment service charge',
                                            value:
                                                '- RM ${_formatMoney(serviceFee)}',
                                          ),
                                          _receiptInfoRow(
                                            icon: Icons.percent_outlined,
                                            title:
                                                'Platform payment charge (7%)',
                                            value:
                                                '- RM ${_formatMoney(platformFee)}',
                                          ),
                                          _receiptInfoRow(
                                            icon: Icons.calculate_outlined,
                                            title: 'New total',
                                            value:
                                                'RM ${_formatMoney(netTotal)}',
                                            showBorder: false,
                                          ),
                                        ] else
                                          _receiptInfoRow(
                                            icon: Icons.calculate_outlined,
                                            title: 'Total',
                                            value: 'RM ${_formatMoney(total)}',
                                            showBorder: false,
                                          ),
                                      ]),
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
                  if (!hideReceiptActions)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: _receiptPremiumCardDecoration(),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _downloadReceiptPdf(
                                  paymentId,
                                  sheetContext,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Download receipt',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    _shareReceiptPdf(paymentId, sheetContext),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentGold,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Share receipt',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<bool> _confirmHideBooking(String bookingId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hide this booking?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This hides the booking from your history but keeps the data for records.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    backgroundColor: const Color(0xFFF4B63D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    elevation: 0,
                  ),
                  child: const Text('Hide'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == true) {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({'hidden': true});
    }
    return result ?? false;
  }

  Future<bool> _confirmHidePayment(String paymentId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this payment?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will remove the payment from your history.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    backgroundColor: const Color(0xFFF4B63D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    elevation: 0,
                  ),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == true) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        setState(() => _hiddenPaymentIds.add(paymentId));
        await FirebaseFirestore.instance
            .collection('payments')
            .doc(paymentId)
            .set({
              'hiddenFor': {uid: true},
            }, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance
            .collection('payments')
            .doc(paymentId)
            .set({'hidden': true}, SetOptions(merge: true));
      }
    }
    return result ?? false;
  }

  Widget _buildDeleteBackground(VoidCallback onDelete) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDelete,
        borderRadius: _historyCardBorderRadius,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: _historyCardBorderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: const [
              Icon(Icons.delete_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeableHistoryCard extends StatefulWidget {
  const _SwipeableHistoryCard({
    required this.backgroundBuilder,
    required this.child,
    required this.onDeletePressed,
  });

  final Widget Function(VoidCallback onDeleteTap) backgroundBuilder;
  final Widget child;
  final Future<void> Function() onDeletePressed;

  @override
  State<_SwipeableHistoryCard> createState() => _SwipeableHistoryCardState();
}

class _SwipeableHistoryCardState extends State<_SwipeableHistoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _processingDelete = false;

  double get _offset => _controller.value * _historyCardSwipeMax;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, {Curve curve = Curves.easeOut}) {
    _controller.animateTo(
      (target / _historyCardSwipeMax).clamp(0, 1),
      duration: const Duration(milliseconds: 180),
      curve: curve,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_processingDelete) return;
    final delta = details.delta.dx * 1.2;
    final newOffset = (_offset + delta).clamp(0, _historyCardSwipeMax);
    _controller.value = newOffset / _historyCardSwipeMax;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_processingDelete) return;
    if (_offset >= _historyCardSwipeThreshold) {
      _animateTo(_historyCardSwipeThreshold);
    } else {
      _animateTo(_offset);
    }
  }

  Future<void> _handleDeleteTap() async {
    if (_processingDelete) return;
    _processingDelete = true;
    try {
      await widget.onDeletePressed();
    } finally {
      _processingDelete = false;
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(child: widget.backgroundBuilder(_handleDeleteTap)),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_offset, 0),
                  child: child,
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryNoticeCard extends StatelessWidget {
  const _HistoryNoticeCard({
    required this.message,
    required this.statusLabel,
    this.requestedAt,
    this.icon = Icons.check_circle_outline,
    this.iconColor = _reminderIconColor,
    this.onDelete,
    this.footer,
  });

  final String message;
  final String statusLabel;
  final DateTime? requestedAt;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onDelete;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final dateLabel = requestedAt != null
        ? DateFormat('dd MMM yyyy • hh:mm a').format(requestedAt!)
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(icon, color: iconColor),
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (dateLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              dateLabel,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: _segmentIndicatorColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.bookingStatus});

  final String bookingStatus;

  String get _normalizedBooking => bookingStatus.trim().toLowerCase();

  bool get _isCancelled => _normalizedBooking.contains('cancel');

  String get _label {
    if (_isCancelled) return 'Cancelled';
    return switch (_normalizedBooking) {
      'completed' || 'done' || 'finished' => 'Completed',
      'ongoing' || 'in_progress' => 'Ongoing',
      'assigned' => 'Assigned',
      'pending' => 'Pending',
      'scheduled' => 'Scheduled',
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

class _PaymentStatusChip extends StatelessWidget {
  const _PaymentStatusChip({required this.paymentStatus});

  final String paymentStatus;

  String get _normalized => paymentStatus.trim().toLowerCase();

  bool get _isPaid => _normalized == 'paid' || _normalized == 'success';

  bool get _isCancelled =>
      _normalized.contains('cancel') || _normalized.contains('refund');

  bool get _isFailed => _normalized == 'failed';

  String get _label {
    if (_isPaid) return 'Paid';
    if (_isFailed) return 'Failed';
    if (_normalized == 'refund_requested') return 'Refund';
    if (_isCancelled) return 'Cancelled';
    if (_normalized == 'pending') return 'Pending';
    return paymentStatus.trim().isEmpty ? 'Status' : paymentStatus.trim();
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

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

Widget _buildEmptyReminder({
  required IconData icon,
  required String headline,
  required String explanation,
  Color iconColor = _reminderIconColor,
}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 10),
            Text(
              headline,
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
    ),
  );
}
