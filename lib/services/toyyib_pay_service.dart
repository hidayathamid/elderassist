import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Minimal ToyyibPay integration stub.
/// Supply valid `categoryKey` and `secretKey` via flavor/environment config.
class ToyyibPayService {
  ToyyibPayService({
    required this.categoryKey,
    required this.secretKey,
  });

  final String categoryKey;
  final String secretKey;

  String get _categoryOrEnv =>
      categoryKey.isNotEmpty ? categoryKey : _envValue('TOYYIBPAY_CATEGORY_CODE') ?? '';

  String get _secretOrEnv =>
      secretKey.isNotEmpty ? secretKey : _envValue('TOYYIBPAY_SECRET_KEY') ?? '';

  String? _envValue(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _categoryOrEnv.isNotEmpty && _secretOrEnv.isNotEmpty;

  /// Creates a ToyyibPay bill and returns the payment URL.
  /// Replace [callbackUrl] with your server callback.
  Future<String> createBill({
    required String billName,
    required String description,
    required int amount,
    required String userEmail,
  }) async {
    final url = Uri.parse('https://dev.toyyibpay.com/index.php/api/createBill');
    final response = await http.post(
      url,
      body: {
        'userSecretKey': _secretOrEnv,
        'categoryCode': _categoryOrEnv,
        'billName': billName,
        'billDescription': description,
        'billAmount': amount.toString(),
        'billTo': userEmail,
        // Add other required parameters here.
      },
    );
    if (response.statusCode != 200) {
      throw Exception('ToyyibPay request failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map && first['BillCode'] != null) {
        return first['BillCode'] as String;
      }
    } else if (decoded is Map && decoded['BillCode'] != null) {
      return decoded['BillCode'] as String;
    }
    throw Exception(
      'Unable to parse ToyyibPay response (${response.body})',
    );
  }
}
