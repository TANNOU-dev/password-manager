plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tannou.password_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tannou.password_manager"

        // Android 10, et non le défaut 24 de Flutter.
        //
        // Imposé par flutter_autofill_service, qui déclare minSdkVersion 29 :
        // laisser 24 fait échouer la fusion des manifestes au build. Conséquence
        // assumée — les appareils sous Android 7, 8 et 9 ne peuvent plus
        // installer l'app.
        //
        // Pour revenir en arrière : retirer flutter_autofill_service, remettre
        // `flutter.minSdkVersion`, et supprimer lib/features/autofill/.
        minSdk = 29

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
