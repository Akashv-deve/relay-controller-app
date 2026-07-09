import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.grey[100],
    cardColor: Colors.white,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blueAccent,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
  );
}