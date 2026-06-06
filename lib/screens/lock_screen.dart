import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final List<int> _pin = [];
  bool _isBiometricAvailable = false;
  String _errorMessage = '';
  String _correctPin = '123456'; // Loaded from settings, fallback to default

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _correctPin = prefs.getString('app_pin') ?? '123456';
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBiometrics();
    });
  }

  Future<void> _checkBiometrics() async {
    final available = await AuthService.isBiometricsSupported();
    setState(() {
      _isBiometricAvailable = available;
    });
    if (available) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    final authenticated = await AuthService.authenticateBiometric(
      reason: 'Please authenticate to open DeliMap',
    );
    if (authenticated) {
      _unlockApp();
    }
  }

  void _unlockApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _onKeyPress(int number) {
    if (_pin.length < 6) {
      setState(() {
        _pin.add(number);
        _errorMessage = '';
      });

      if (_pin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onDeletePress() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin.removeLast();
        _errorMessage = '';
      });
    }
  }

  void _verifyPin() {
    final enteredPin = _pin.join();
    if (enteredPin == _correctPin) {
      _unlockApp();
    } else {
      setState(() {
        _pin.clear();
        _errorMessage = 'Incorrect PIN. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // Logo & Tagline
            const Icon(
              Icons.local_shipping_outlined,
              size: 72,
              color: Color(0xFFF5A623),
            ),
            const SizedBox(height: 16),
            const Text(
              'DELIMAP',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4.0,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan. Route. Deliver.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E93),
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            // PIN Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF5A623), width: 2),
                    color: isFilled ? const Color(0xFFF5A623) : Colors.transparent,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            // Error Message
            Text(
              _errorMessage,
              style: const TextStyle(color: Color(0xFFFF453A), fontSize: 14),
            ),
            const Spacer(),
            // Numeric Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (var row = 0; row < 3; row++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var col = 1; col <= 3; col++)
                            _buildKey(row * 3 + col),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Biometrics / Left helper key
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: _isBiometricAvailable
                              ? IconButton(
                                  icon: const Icon(Icons.fingerprint, color: Color(0xFFF5A623), size: 32),
                                  onPressed: _authenticate,
                                )
                              : const SizedBox(),
                        ),
                        _buildKey(0),
                        // Backspace Key
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: IconButton(
                            icon: const Icon(Icons.backspace_outlined, color: Colors.white, size: 24),
                            onPressed: _onDeletePress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(int value) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyPress(value),
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2C2C2E), width: 1),
            color: const Color(0xFF1C1C1E),
          ),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
