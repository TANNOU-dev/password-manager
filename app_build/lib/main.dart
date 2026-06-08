import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1B2A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PassVaultApp());
}

class PassVaultApp extends StatelessWidget {
  const PassVaultApp({super.key});

  // ── Design System PassVault ──────────────────────────────────
  static const Color deepNavy = Color(0xFF0D1B2A);
  static const Color brandNavy = Color(0xFF051423);
  static const Color brandSlate = Color(0xFF1E2D3D);
  static const Color brandBorder = Color(0xFF2A3F54);
  static const Color brandGrey = Color(0xFF8A9BB0);
  static const Color electricBlue = Color(0xFF1A73E8);
  static const Color brandGreen = Color(0xFF34A853);
  static const Color surfaceVariant = Color(0xFF273646);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PassVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.inter().fontFamily,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: deepNavy,
        colorScheme: const ColorScheme.dark(
          primary: electricBlue,
          onPrimary: Colors.white,
          surface: deepNavy,
          onSurface: Color(0xFFD4E4F9),
          outline: brandBorder,
          error: errorContainer,
          onError: onErrorContainer,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: deepNavy,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.01,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: brandSlate,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: brandBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: brandBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: electricBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            letterSpacing: 0.5,
            color: brandGrey,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: brandGrey,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: electricBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: brandSlate,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: brandBorder, width: 0.5),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.02,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.01,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFFD4E4F9),
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFFD4E4F9),
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFFD4E4F9),
            height: 1.43,
          ),
          labelMedium: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: Color(0xFF8A9BB0),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
