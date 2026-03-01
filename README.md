# namer_app

A new Flutter project.

## Firebase Setup

This project uses Firebase. The `lib/firebase_options.dart` file is gitignored because it
contains API keys. You must generate it locally before building or running the app.

1. Install the FlutterFire CLI:
   ```sh
   dart pub global activate flutterfire_cli
   ```
2. Run FlutterFire configure from the project root:
   ```sh
   flutterfire configure
   ```
   This regenerates `lib/firebase_options.dart` with your project's credentials.

3. The file is gitignored — every developer and CI environment must run `flutterfire configure`
   once after cloning.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
