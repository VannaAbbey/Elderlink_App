plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") //added for firebase backend - july 30, 2025
}

dependencies { 
  // Core library desugaring for flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")  // << ADD THIS LINE
    
  // Import the Firebase BoM
  implementation(platform("com.google.firebase:firebase-bom:34.0.0")) //added for firebase backend - july 30, 2025

  // Firebase Authentication
  implementation("com.google.firebase:firebase-auth")
  
  // Google Sign-In
  implementation("com.google.android.gms:play-services-auth:20.7.0")

  // Core library desugaring for notifications
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

  // TODO: Add the dependencies for Firebase products you want to use
  // When using the BoM, don't specify versions in Firebase dependencies
  // https://firebase.google.com/docs/android/setup#available-libraries
}

android {
    namespace = "com.example.elderlink_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8   // << change from 11
        targetCompatibility = JavaVersion.VERSION_1_8   // << change from 11
        isCoreLibraryDesugaringEnabled = true           // << ADD THIS LINE
    }

    kotlinOptions {
        jvmTarget = "1.8"                               // << change from 11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.group8.elderlink_app" //updated package name - july 30, 2025
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true    // << ADD THIS LINE
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
