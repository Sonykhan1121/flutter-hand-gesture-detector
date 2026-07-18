import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ultralytics uses LiteRT Next 2.x, while hand_detection/object_detection use
// the classic 1.4.2 C runtime through Dart FFI. Gradle cannot resolve both AAR
// versions normally, so extract only the classic native library alongside 2.x.
val classicLiteRtAar by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
    isTransitive = false
}

dependencies {
    classicLiteRtAar("com.google.ai.edge.litert:litert:1.4.2@aar")
}

val extractClassicLiteRtJni by tasks.registering(Sync::class) {
    from({ classicLiteRtAar.files.map { zipTree(it) } }) {
        include("jni/**/libtensorflowlite_jni.so")
        eachFile { path = path.substringAfter("jni/") }
        includeEmptyDirs = false
    }
    into(layout.buildDirectory.dir("generated/classicLiteRtJni"))
}

android {
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasReleaseKeystore = keystorePropertiesFile.exists()

    if (hasReleaseKeystore) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    namespace = "com.grozziie.gesturedetector.gesture_detector"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.grozziie.gesturedetector.gesture_detector"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += setOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    packaging {
        jniLibs {
            pickFirsts += "**/libc++_shared.so"
        }
    }

    sourceSets.getByName("main").jniLibs.srcDir(
        layout.buildDirectory.dir("generated/classicLiteRtJni"),
    )

//    signingConfigs {
//        if (hasReleaseKeystore) {
//            create("release") {
//                keyAlias = keystoreProperties["keyAlias"] as String
//                keyPassword = keystoreProperties["keyPassword"] as String
//                storeFile = file(keystoreProperties["storeFile"] as String)
//                storePassword = keystoreProperties["storePassword"] as String
//            }
//        }
//    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true

            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

tasks.named("preBuild").configure {
    dependsOn(extractClassicLiteRtJni)
}
