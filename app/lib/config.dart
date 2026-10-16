import 'package:flutter/foundation.dart';

/// Brand name and tagline shown across the UI. Change them here only.
const String kAppName = 'Aurora';
const String kTagline = 'Awaken Your Intellect.';

/// Backend base URL.
///
/// Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
/// The iOS simulator reaches the host as `localhost`; the Android emulator
/// needs `10.0.2.2`; a physical phone needs your computer's LAN address.
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:4000';
  }
  return 'http://localhost:4000';
}
