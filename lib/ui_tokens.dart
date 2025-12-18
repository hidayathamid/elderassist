import 'package:flutter/material.dart';

class UiTokens {
  // ===== COLORS (ikut Profile Overview) =====
  static const Color textDark = Color(0xFF1B1D29);
  static const Color teal = Color(0xFF00A8A7);
  static const Color gold = Color(0xFFF4B63D);
  static const Color divider = Color(0xFFEDEDED);

  // ===== FONT SIZES =====
  static const double fs10_5 = 10.5;
  static const double fs11 = 11;
  static const double fs12 = 12;
  static const double fs14 = 14;
  static const double fs14_5 = 14.5;
  static const double fs15 = 15;
  static const double fs16 = 16;
  static const double fs18 = 18;

  // ===== ICON SIZES =====
  static const double icon16 = 16;
  static const double icon20 = 20;
  static const double icon24 = 24;

  // ===== SPACING =====
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s24 = 24;

  // ===== HEIGHTS =====
  static const double rowH = 50;
  static const double chipH = 26;
  static const double serviceH = 44;
  static const double buttonVPad = 14;

  // ===== RADIUS =====
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r18 = 18;
  static const double r24 = 24;

  // ===== TEXT STYLES (ikut feel Profile Overview) =====
  static const TextStyle title = TextStyle(
    fontSize: fs16,
    fontWeight: FontWeight.w700,
    color: textDark,
  );

  static const TextStyle section = TextStyle(
    fontSize: fs14_5,
    fontWeight: FontWeight.w600,
    color: textDark,
  );

  static const TextStyle body = TextStyle(
    fontSize: fs14,
    fontWeight: FontWeight.w500,
    color: textDark,
  );

  static const TextStyle small = TextStyle(fontSize: fs12, color: textDark);

  static const TextStyle chip = TextStyle(
    fontSize: fs10_5,
    fontWeight: FontWeight.w600,
  );
}
