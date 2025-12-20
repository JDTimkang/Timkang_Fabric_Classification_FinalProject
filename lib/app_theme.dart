import 'package:flutter/material.dart';

/// Global theme and fabric taxonomy metadata.
///
/// The `classNames` and `classColors` now represent fabric types instead of
/// NBA teams. They are aligned with the app assets in `assets/images/` and the
/// model labels shipped in `assets/labels.txt`.
class AppColors {
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color primaryIndigo = Color(0xFF6A5AE0);
  static const Color accentTeal = Color(0xFF3EDBF0);
  static const Color dark = Color(0xFF1E1E2F);
  // Soft nude-inspired palette for light mode backgrounds.
  static const Color backgroundLight = Color(0xFFFFF7EF); // very light nude
  static const Color cardBackground = Color(0xFFFFFBF6); // slightly deeper nude
  static const Color textPrimary = Color(0xFF1E1E2F);
  static const Color textSecondary = Color(0xFF6B6F80);

  /// Fabric swatch colors (roughly matched to the fabric type).
  static const List<Color> classColors = [
    Color(0xFF8D6E63), // Canvas - warm brown
    Color(0xFFF8BBD0), // Chiffon - soft pink
    Color(0xFFB0BEC5), // Damask - muted grey blue
    Color(0xFF455A64), // Denim - deep blue-grey
    Color(0xFF5D4037), // Leather - dark brown
    Color(0xFFBCAAA4), // Linen - light beige
    Color(0xFFCE93D8), // Silk - soft purple
    Color(0xFF795548), // Velvet - rich brown
    Color(0xFFD7CCC8), // Wool - warm light brown
    Color(0xFFFFF9C4), // Lace - delicate cream
  ];

  /// Fabric class names used across detection, history and analytics.
  ///
  /// These should mirror the entries in `assets/labels.txt` and the
  /// image names in `assets/images/*.png` where possible.
  static const List<String> classNames = [
    'Canvas',
    'Chiffon',
    'Damask',
    'Denim',
    'Leather',
    'Linen',
    'Silk',
    'Velvet',
    'Wool',
    'Lace',
  ];
}
