import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome_setup_screen.dart';
import 'screens/home_screen.dart';

class DeliMapApp extends StatelessWidget {
  const DeliMapApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeliMap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        primaryColor: const Color(0xFFF5A623),
        colorScheme: const ColorScheme.dark().copyWith(
          primary: const Color(0xFFF5A623),
          secondary: const Color(0xFFF5A623),
          surface: const Color(0xFF1C1C1E),
          background: const Color(0xFF0D0D0D),
          error: const Color(0xFFFF453A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFF8E8E93)),
        ),
      ),
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({Key? key}) : super(key: key);

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  bool _firstRun = true;
  bool _appLock = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _firstRun = !(prefs.getBool('first_run_completed') ?? false);
        _appLock = prefs.getBool('app_lock_enabled') ?? true;
        _isLoading = false;
      });
    } catch (e) {
      print('AppInitializer error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF5A623)),
        ),
      );
    }

    if (_firstRun) {
      return const WelcomeSetupScreen();
    }

    if (_appLock) {
      return const LockScreen();
    }

    return const HomeScreen();
  }
}
