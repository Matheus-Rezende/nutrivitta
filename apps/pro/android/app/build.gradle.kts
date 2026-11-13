import java.util.Properties

// Assinatura fixa do APK: as atualizações só instalam por cima quando todas as
// versões usam a mesma chave. Vem de android/key.properties (local) ou das
// variáveis NV_KEYSTORE_PATH / NV_KEYSTORE_PASSWORD (GitHub Actions).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signing(prop: String, env: String): String? =
    keyProps.getProperty(prop) ?: System.getenv(env)?.takeIf { it.isNotBlank() }
val releaseStore = signing("storeFile", "NV_KEYSTORE_PATH")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nutrivitta.pro"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nutrivitta.pro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24) // login Google (Credential Manager)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signing("storePassword", "NV_KEYSTORE_PASSWORD")
                keyAlias = signing("keyAlias", "NV_KEY_ALIAS") ?: "nutrivitta"
                keyPassword = signing("keyPassword", "NV_KEY_PASSWORD") ?: storePassword
            }
        }
    }

    buildTypes {
        release {
            // Sem a chave (ex.: na sua máquina), usa a de depuração para `flutter run --release` funcionar.
            signingConfig = signingConfigs.getByName(if (releaseStore != null) "release" else "debug")
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
