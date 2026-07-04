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
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Deep Blue
          primary: const Color(0xFF0D47A1),
          secondary: const Color(0xFFFFD700), // Gold
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Deep Blue
          primary: const Color(0xFF1976D2),
          secondary: const Color(0xFFFFD700), // Gold
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
