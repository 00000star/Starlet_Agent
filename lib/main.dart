import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StarletApp());
}

class StarletApp extends StatelessWidget {
  const StarletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starlet',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Force dark mode for premium aesthetic
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF), // Neon Purple
          secondary: Color(0xFF00FFC6), // Cyan Neon
          surface: Color(0xFF151522),
          error: Color(0xFFFF3366),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, color: Colors.white, letterSpacing: 0.3),
          bodyMedium: TextStyle(fontSize: 15, color: Colors.white70, letterSpacing: 0.2),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
