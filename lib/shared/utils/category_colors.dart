import 'package:flutter/material.dart';

/// Dark, distinguishable background colors assigned to bank categories so
/// each bank reads as a different hue without competing with the app theme.
abstract final class CategoryColors {
  static const List<Color> palette = [
    Color(0xFF24534D), // deep mint
    Color(0xFF294D6B), // deep blue
    Color(0xFF5A4630), // walnut
    Color(0xFF5A3D4A), // rosewood
    Color(0xFF443B63), // indigo
    Color(0xFF245B5A), // deep aqua
    Color(0xFF5C4030), // clay
    Color(0xFF4A4E32), // olive
    Color(0xFF36536A), // steel blue
    Color(0xFF51413A), // cocoa
  ];

  static Color forId(String id) {
    var hash = 0;
    for (final code in id.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  static Color foregroundFor(Color background) {
    // Keep text readable if the palette is extended with lighter colors.
    return background.computeLuminance() < .45
        ? const Color(0xFFF4F7F5)
        : const Color(0xFF17211E);
  }
}
