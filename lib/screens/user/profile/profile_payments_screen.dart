import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emergencies_disability_assistance_app/models/payment_document_target.dart';
import 'package:emergencies_disability_assistance_app/utils/service_preferences.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

const Color _cardBorderColor = Color(0xFFE0E0E0);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _reminderIconColor = Color(0xFF00A8A7);
final TextStyle _payoutHintStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText.withValues(alpha: 0.45),
);
const Color _statusPaid = Color(0xFF2BB673);
const Color _statusPending = Color(0xFFF4B63D);
const Color _statusCancelled = Color(0xFFF25C54);
const double _segmentRadius = 26.0;
const double _segmentHeight = 38.0;
const Color _segmentIndicatorColor = Color(0xFFF4F5F7);
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
    this.target = PaymentDocumentTarget.auto,
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
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedWithdrawDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedPaymentDocs = [];
  Timestamp? _lastSeenPaymentHistoryAt;
  bool _historySeenInitialized = false;
  TabController? _tabController;

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
              final paymentStatus =
                  (data['paymentStatus'] as String?)?.trim().toUpperCase();
              if (status == 3 || paymentStatus == 'FAILED') continue;
              count++;
            }
            return count;
          });
    }).distinct();
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
    final paymentField = _isCaregiverAccount ? 'caregiverId' : 'userId';
    final baseQuery = FirebaseFirestore.instance
        .collection('payments')
        .where(paymentField, isEqualTo: userId)
        ;
    final stream = _isCaregiverAccount
        ? baseQuery.snapshots()
        : baseQuery.orderBy('updatedAt', descending: true).snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (_cachedPaymentDocs.isNotEmpty) {
            final visibleDocs = _cachedPaymentDocs.where((doc) {
              final data = doc.data();
              if ((data['hidden'] as bool?) == true) return false;
              final status = (data['status'] as num?)?.toInt();
              final paymentStatus =
                  (data['paymentStatus'] as String?)?.trim().toUpperCase();
              return !(status == 3 || paymentStatus == 'FAILED');
            }).toList();
            return _buildHistoryList(visibleDocs, const [], const []);
          }
          return _historyPlaceholder(
            'Unable to load payments.',
            'Please check your connection and try again.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? const [];
        final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(
          docs,
        )..sort((a, b) {
            final tsA = a.data()['updatedAt'] as Timestamp?;
            final tsB = b.data()['updatedAt'] as Timestamp?;
            if (tsA == null && tsB == null) return 0;
            if (tsA == null) return 1;
            if (tsB == null) return -1;
            return tsB.compareTo(tsA);
          });
        if (docs.isNotEmpty) {
          _cachedPaymentDocs = sortedDocs;
        }

        final lastSeen = _lastSeenPaymentHistoryAt;
        bool isNew(Map<String, dynamic> data) {
          if (lastSeen == null) return false;
          final updatedAt = data['updatedAt'] as Timestamp?;
          return updatedAt != null && updatedAt.compareTo(lastSeen) > 0;
        }

        bool isCancelled(Map<String, dynamic> data) {
          final status = (data['status'] as num?)?.toInt();
          if (status == 3) return true;
          final paymentStatus =
              (data['paymentStatus'] as String?)?.trim().toUpperCase();
          return paymentStatus == 'CANCELLED' || paymentStatus == 'CANCELED';
        }

        bool isPaid(Map<String, dynamic> data) {
          final status = (data['status'] as num?)?.toInt();
          if (status == 1) return true;
          final paymentStatus =
              (data['paymentStatus'] as String?)?.trim().toUpperCase();
          return paymentStatus == 'PAID' || paymentStatus == 'SUCCESS';
        }

        final visibleDocs = sortedDocs.where((doc) {
          final data = doc.data();
          if ((data['hidden'] as bool?) == true) return false;
          final status = (data['status'] as num?)?.toInt();
          final paymentStatus =
              (data['paymentStatus'] as String?)?.trim().toUpperCase();
          return !(status == 3 || paymentStatus == 'FAILED');
        }).toList();

        final cancelledCount =
            sortedDocs
                .where((doc) => isCancelled(doc.data()) && isNew(doc.data()))
                .length;
        final paidCount =
            sortedDocs.where((doc) => isPaid(doc.data()) && isNew(doc.data())).length;

        final notices = <_HistoryNoticeCard>[];
        if (!_isCaregiverAccount && cancelledCount > 0) {
          notices.add(
            _HistoryNoticeCard(
              icon: Icons.cancel_outlined,
              iconColor: _statusCancelled,
              statusLabel: 'Cancelled',
              message: cancelledCount == 1
                  ? 'A payment was cancelled. You can place the booking again anytime.'
                  : '$cancelledCount payments were cancelled. You can place those bookings again anytime.',
            ),
          );
        }
        if (_isCaregiverAccount && paidCount > 0) {
          notices.add(
            _HistoryNoticeCard(
              icon: Icons.check_circle_outline,
              iconColor: _statusPaid,
              statusLabel: 'Paid',
              message: paidCount == 1
                  ? 'You received a new successful payment.'
                  : 'You received $paidCount new successful payments.',
            ),
          );
        }
        if (_isCaregiverAccount && cancelledCount > 0) {
          notices.add(
            _HistoryNoticeCard(
              icon: Icons.event_busy_outlined,
              iconColor: _statusCancelled,
              statusLabel: 'Cancelled',
              message: cancelledCount == 1
                  ? 'A booking payment was cancelled.'
                  : '$cancelledCount booking payments were cancelled.',
            ),
          );
        }
        if (_historyNotificationMessage != null) {
          notices.add(
            _HistoryNoticeCard(
              message: _historyNotificationMessage!,
              statusLabel: 'Pending',
            ),
          );
        }

        final withdrawStream = _isCaregiverAccount
            ? FirebaseFirestore.instance
                  .collection('withdrawRequests')
                  .where('caregiverId', isEqualTo: userId)
                  .orderBy('requestedAt', descending: true)
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
            final latestWithdrawDocs = withdrawSnapshot.data?.docs ?? [];
            if (latestWithdrawDocs.isNotEmpty) {
              _cachedWithdrawDocs = latestWithdrawDocs;
            }
            final effectiveWithdrawDocs = latestWithdrawDocs.isNotEmpty
                ? latestWithdrawDocs
                : _cachedWithdrawDocs;
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
    final newCount = lastSeen == null
        ? 0
        : visibleDocs.where((doc) {
            final updatedAt = doc.data()['updatedAt'] as Timestamp?;
            return updatedAt != null && updatedAt.compareTo(lastSeen) > 0;
          }).length;
    if (newCount > 0) {
      entries.add(
        _HistoryNoticeCard(
          icon: Icons.notifications_active_outlined,
          iconColor: _segmentIndicatorColor,
          statusLabel: 'New updates',
          message:
              'You have $newCount new ${newCount == 1 ? 'payment update' : 'payment updates'}.',
        ),
      );
    }
    for (final doc in withdrawDocs) {
      entries.add(_buildWithdrawHistoryCard(doc));
    }
    for (final doc in visibleDocs) {
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
    return _HistoryNoticeCard(
      icon: Icons.account_balance_wallet_outlined,
      iconColor: _accentGold,
      statusLabel: _withdrawStatusLabel(data),
      message: _withdrawRequestMessage(data),
      requestedAt: requestedAt,
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
    switch (normalized) {
      case 'approved':
        return 'Your withdrawal request has been approved. Funds will reach your payout account shortly.';
      case 'rejected':
      case 'failed':
        return 'Your withdrawal request was declined. Please contact support for more information.';
      default:
        return 'Withdrawal request sent. Please allow up to 24 hours for admin verification.';
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
    final reason = (data['cancellationReason'] as String?) ?? '';
    final personName = (data['personName'] as String?) ?? '';
    final caregiverName = (data['caregiverName'] as String?) ?? '';
    final personAddress = (data['personAddress'] as String?) ?? '';
    final caregiverPhoto = (data['caregiverPhoto'] as String?)?.trim();
    final date = (data['date'] as String?) ?? '';
    final time = (data['time'] as String?) ?? '';
    final notes = (data['notes'] as String?) ?? '';
    final showRefundInProgress = bookingStatus.contains('CANCEL');

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
                    DefaultProfileAvatar(
                      radius: 20,
                      photoUrl: caregiverPhoto?.isNotEmpty == true
                          ? caregiverPhoto
                          : null,
                      label: caregiverName.isNotEmpty
                          ? caregiverName
                          : (service.isNotEmpty ? service : '?'),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusChip(bookingStatus: bookingStatus),
                        const SizedBox(height: 6),
                        isNew
                            ? const _CountPill(count: 1)
                            : const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.black38,
                              ),
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
                      DefaultProfileAvatar(
                        radius: 16,
                        label: personName.isNotEmpty
                            ? personName
                            : caregiverName,
                      ),
                      const SizedBox(width: 8),
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
    final booking = (data['booking'] as Map?)?.cast<String, dynamic>() ?? const {};
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
    final amount = (data['amount'] as num?)?.toDouble() ??
        (booking['servicePrice'] as num?)?.toDouble() ??
        0.0;
    final paymentStatus =
        (data['paymentStatus'] as String?)?.trim().toUpperCase() ?? 'PENDING';
    final bookingStatus =
        (data['bookingStatus'] as String?)?.trim().toUpperCase() ?? '';

    final statusLabel = paymentStatus == 'PAID' ? 'Paid' : 'Pending';
    final statusColor = paymentStatus == 'PAID' ? _statusPaid : _statusPending;

    return _SwipeableHistoryCard(
      backgroundBuilder: (onDeleteTap) => _buildDeleteBackground(onDeleteTap),
      onDeletePressed: () => _confirmHidePayment(id),
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
                    DefaultProfileAvatar(
                      radius: 20,
                      photoUrl: caregiverPhoto?.isNotEmpty == true
                          ? caregiverPhoto
                          : null,
                      label: caregiverName.isNotEmpty
                          ? caregiverName
                          : (service.isNotEmpty ? service : '?'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caregiverName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _profileDarkText,
                            ),
                          ),
                          if (service.isNotEmpty)
                            Text(
                              service,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _PaymentStatusChip(label: statusLabel, color: statusColor),
                        const SizedBox(height: 6),
                        isNew
                            ? const _CountPill(count: 1)
                            : const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.black38,
                              ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      'RM ${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _profileDarkText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    const Spacer(),
                    if (bookingStatus.isNotEmpty)
                      Text(
                        bookingStatus,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
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
          'Hide this payment?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This hides the payment entry from your history.',
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
          .collection('payments')
          .doc(paymentId)
          .set({'hidden': true}, SetOptions(merge: true));
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
  });

  final String message;
  final String statusLabel;
  final DateTime? requestedAt;
  final IconData icon;
  final Color iconColor;

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

  Color get _dotColor {
    if (_isCancelled) return _statusCancelled;
    return switch (_normalizedBooking) {
      'completed' || 'done' || 'finished' => _statusPaid,
      'ongoing' || 'in_progress' || 'assigned' => _statusPending,
      'pending' || 'scheduled' => _statusPending,
      _ => Colors.grey.shade600,
    };
  }

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

class _PaymentStatusChip extends StatelessWidget {
  const _PaymentStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

Widget _buildEmptyReminder({
  required IconData icon,
  required String headline,
  required String explanation,
  Color iconColor = _reminderIconColor,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
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
          style: const TextStyle(fontSize: 12, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
