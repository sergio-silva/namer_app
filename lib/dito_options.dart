// Dito API credentials.
// Pass at build/run time via --dart-define:
//   flutter run \
//     --dart-define=DITO_API_KEY=your_key \
//     --dart-define=DITO_API_SECRET=your_secret
class DitoOptions {
  static const String appKey = String.fromEnvironment('DITO_API_KEY');
  static const String appSecret = String.fromEnvironment('DITO_API_SECRET');
}
