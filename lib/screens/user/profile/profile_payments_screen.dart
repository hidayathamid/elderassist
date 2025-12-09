import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/toyyib_pay_service.dart';

const Color _tealAccent = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);

class ProfilePaymentsScreen extends StatefulWidget {
  const ProfilePaymentsScreen({super.key});

  @override
  State<ProfilePaymentsScreen> createState() => _ProfilePaymentsScreenState();
}

class _ProfilePaymentsScreenState extends State<ProfilePaymentsScreen> {
  static const String _categoryKey = String.fromEnvironment(
    'TOYYIB_CATEGORY_KEY',
  );
  static const String _secretKey = String.fromEnvironment('TOYYIB_SECRET_KEY');

  late final ToyyibPayService _toyyibPayService = ToyyibPayService(
    categoryKey: _categoryKey,
    secretKey: _secretKey,
  );

  bool _showHistory = false;
  bool _isToyyibPending = false;

  static const List<Map<String, String>> _methods = [
    {'name': 'Maybank', 'desc': 'FPX •••• 4532', 'badge': 'Default'},
    {'name': 'CIMB Bank', 'desc': 'FPX •••• 7891', 'badge': ''},
    {'name': 'Touch \'n Go', 'desc': 'E-Wallet •••• 2345', 'badge': ''},
  ];

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
            color: _profileDarkText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Payments & Billing',
          style: TextStyle(
            color: _profileDarkText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.notifications_none, color: _profileDarkText),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tabBar(),
              const SizedBox(height: 12),
              if (_showHistory) _historySection() else _paymentMethodsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBar() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_showHistory) setState(() => _showHistory = false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _showHistory ? Colors.white : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showHistory
                      ? Colors.grey.withValues(alpha: 0.25)
                      : _tealAccent,
                ),
              ),
              child: Center(
                child: Text(
                  'Payment Methods',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _showHistory ? Colors.black87 : _tealAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (!_showHistory) setState(() => _showHistory = true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _showHistory ? Colors.grey.shade200 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showHistory
                      ? _tealAccent
                      : Colors.grey.withValues(alpha: 0.25),
                ),
              ),
              child: Center(
                child: Text(
                  'History',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _showHistory ? _tealAccent : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paymentMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _activeMethodCard(),
        const SizedBox(height: 10),
        _toyyibPayCTA(),
        const SizedBox(height: 12),
        _dashedAddCard(),
        const SizedBox(height: 12),
        ..._methods.map(
          (method) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _paymentRow(
              name: method['name']!,
              description: method['desc']!,
              badge: method['badge']!,
            ),
          ),
        ),
      ],
    );
  }

  Widget _toyyibPayCTA() {
    final badge = _toyyibPayService.isConfigured
        ? 'ToyyibPay ready'
        : 'Configure ToyyibPay keys';
    return OutlinedButton(
      onPressed: _isToyyibPending ? null : _handleToyyibPay,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: _toyyibPayService.isConfigured
              ? _tealAccent
              : Colors.grey.shade400,
        ),
        foregroundColor: _tealAccent,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Open ToyyibPay checkout',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            badge,
            style: TextStyle(
              fontSize: 12,
              color: _toyyibPayService.isConfigured
                  ? Colors.green
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToyyibPay() async {
    if (!_toyyibPayService.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ToyyibPay keys missing. Set TOYYIB_CATEGORY_KEY/TOYYIB_SECRET_KEY.',
          ),
        ),
      );
      return;
    }
    setState(() => _isToyyibPending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? 'user@example.com';
      final billCode = await _toyyibPayService.createBill(
        billName: 'Wallet top-up',
        description: 'Add funds via ToyyibPay',
        amount: 100,
        userEmail: email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ToyyibPay bill created: $billCode')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ToyyibPay error: $error')));
    } finally {
      if (mounted) {
        setState(() => _isToyyibPending = false);
      }
    }
  }

  Widget _historySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'History',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        _headerCard(),
        const SizedBox(height: 10),
        _historyPlaceholder(),
      ],
    );
  }

  Widget _historyPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: const [
          Icon(Icons.credit_card_outlined, size: 42, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'No recent history',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: const [
          Text(
            'Total Spent This Month',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          SizedBox(height: 4),
          Text(
            'RM 0.00',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '0 completed transactions',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _activeMethodCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.payment, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ToyyibPay FPX',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'Secure payment gateway',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashedAddCard() {
    return InkWell(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.4),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: const [
            Icon(Icons.add, color: Colors.black54, size: 22),
            SizedBox(height: 4),
            Text(
              'Add Payment Method',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow({
    required String name,
    required String description,
    required String badge,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (badge.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
