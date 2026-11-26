plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 148차: 같은 코드로 재고 앱(직원 휴대폰용)도 만듦 — flutter build apk -t lib/main_stock.dart --android-project-arg=godoriApp=stock
//   → 앱 ID kr.godori.stock · 이름 '고도리 재고' (패드 앱 kr.godori.pad와 따로 깔림). 값을 안 주면 지금처럼 패드 앱
val godoriApp = (project.findProperty("godoriApp") as String?) ?: "pad"
val isStockApp = godoriApp == "stock"

android {
    namespace = "kr.godori.pad"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isStockApp) "kr.godori.stock" else "kr.godori.pad" // 49차 (플레이 스토어에 올린 뒤엔 못 바꿈), 148차 재고 앱
        manifestPlaceholders["appLabel"] = if (isStockApp) "고도리 재고" else "고도리"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// 148차: google-services.json에는 kr.godori.pad만 있어서 재고 앱은 그 단계를 건너뜀
//   (Firebase는 앱이 lib/firebase_options.dart 값으로 켜서 없어도 됨. Firebase 콘솔에 kr.godori.stock 앱을 추가하고
//    google-services.json을 다시 받으면 이 블록을 지워도 됨)
if (isStockApp) {
    tasks.configureEach {
        if (name.contains("GoogleServices")) enabled = false
    }
}
