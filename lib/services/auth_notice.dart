import 'package:flutter/foundation.dart';

class AuthNotice {
  static final ValueNotifier<String?> message = ValueNotifier<String?>(null);

  static void set(String next) {
    message.value = next.trim().isEmpty ? null : next.trim();
  }

  static String? take() {
    final current = message.value;
    message.value = null;
    return current;
  }
}

