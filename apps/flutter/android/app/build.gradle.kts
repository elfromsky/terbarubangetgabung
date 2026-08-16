import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // TODO: Finalize namespace/applicationId after registering the final
    // package name in the Firebase project and updating google-services.json.
    // Current value matches the existing Firebase Android app configuration.
    namespace = "com.example.esh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Change to final applicationId (e.g. com.esh.smarthome) once
        // the matching Firebase app and google-services.json are provisioned.
        applicationId = "com.example.esh"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Configure these in android/key.properties before a real release build.
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                val keyProps = Properties()
                keyPropsFile.inputStream().use { keyProps.load(it) }
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing when key.properties is missing so local
            // release builds still work. For a production APK, provide key.properties.
            signingConfig = if (signingConfigs["release"]?.storeFile?.exists() == true) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
