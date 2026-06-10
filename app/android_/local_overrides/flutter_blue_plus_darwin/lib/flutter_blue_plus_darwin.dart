/// Stub for flutter_blue_plus_darwin. See pubspec.yaml in this folder for why.
library;

/// No-op replacement for the real Darwin implementation. Never registered,
/// because this package declares no plugin platforms; it exists only so any
/// import of this library still resolves.
class FlutterBluePlusDarwin {
  static void registerWith() {
    // Intentionally empty: Bluetooth is excluded from iOS builds.
  }
}
