import 'package:flutter/material.dart';

/// Light, distinguishable background colors assigned to bank categories so
/// each bank reads as a different hue while keeping text readable.
abstract final class CategoryColors {
  static const List<Color> palette = [
    Color(0xFFDCEFE3), // mint green
    Color(0xFFDCE8F7), // soft blue
    Color(0xFFFFF0D6), // warm sand
    Color(0xFFFBE3EC), // rose
    Color(0xFFE6E3FA), // lavender
    Color(0xFFE0F2EF), // aqua
    Color(0xFFFFE5D9), // peach
    Color(0xFFF0EDDA), // olive cream
    Color(0xFFE2ECF9), // steel blue
    Color(0xFFF6E3D7), // clay
  ];

  static Color forId(String id) {
    var hash = 0;
    for (final code in id.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  static Color foregroundFor(Color background) {
    // All palette entries are light; use a fixed dark ink tone.
    return const Color(0xFF1B2B24);
  }
}
