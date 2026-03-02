plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.namer_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.namer_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 25 // dito_sdk requires minSdk >= 25 (was flutter.minSdkVersion = 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Dito credentials via env var or local.properties (uncomment when not hardcoded in AndroidManifest.xml)
        // import java.util.Properties  // add this import at the top of the file if needed
        // val localProperties = java.util.Properties()
        // val localPropertiesFile = rootProject.file("local.properties")
        // if (localPropertiesFile.exists()) {
        //     localProperties.load(localPropertiesFile.inputStream())
        // }
        // val ditoApiKey = System.getenv("DITO_API_KEY")
        //     ?: (localProperties.getProperty("DITO_API_KEY") ?: "")
        // val ditoApiSecret = System.getenv("DITO_API_SECRET")
        //     ?: (localProperties.getProperty("DITO_API_SECRET") ?: "")
        // manifestPlaceholders["DITO_API_KEY"] = ditoApiKey
        // manifestPlaceholders["DITO_API_SECRET"] = ditoApiSecret
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Required for CustomMessagingService.kt to access FlutterFirebaseMessagingService
    implementation(project(":firebase_messaging"))
    // Required for CustomMessagingService.kt to access RemoteMessage and FirebaseMessagingService
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
