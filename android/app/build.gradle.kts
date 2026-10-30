import java.util.Properties
import java.io.FileInputStream
import java.io.InputStreamReader

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material is provided out-of-band (CI secrets or local
// android/key.properties); it must never be committed to the repository.
// Read as UTF-8 so non-ASCII keystore paths survive; Properties.load(stream)
// would decode them as ISO-8859-1 and mangle the path.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        InputStreamReader(FileInputStream(file), Charsets.UTF_8).use { load(it) }
    }
}

/**
 * key.properties 里的 storeFile 允许两种写法：
 * - 绝对路径：CI 从 Secrets 还原 keystore 到临时目录后写绝对路径；
 * - 相对路径：本地测试密钥放在 android/keystore/ 下，相对 android/ 解析。
 *
 * 注意 android {} 块内的 file() 相对的是 android/app/，直接用会把
 * "keystore/local-test.jks" 解析到 android/app/keystore/，因此统一走这里。
 */
fun resolveStoreFile(raw: String): File {
    val candidate = File(raw)
    return if (candidate.isAbsolute) candidate else rootProject.file(raw)
}

// 本地测试签名标记：带该标记的构建会在版本名后追加 -local，
// 避免把本地测试密钥签出的包误当成正式发布包分发（签名不同，无法覆盖升级）。
val isLocalTestSigning =
    keystoreProperties["storeFile"] != null &&
        keystoreProperties.getProperty("localTest") == "true"

android {
    namespace = "com.sundys.kabao"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sundys.kabao"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        // 本地测试签名时在版本名后加 -local，与正式发布包区分开。
        versionName = if (isLocalTestSigning) {
            "${flutter.versionName}-local"
        } else {
            flutter.versionName
        }
    }

    buildTypes {
        release {
            val hasReleaseSigning = keystoreProperties["storeFile"] != null
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = resolveStoreFile(
                        keystoreProperties["storeFile"] as String,
                    )
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                }
            } else {
                // Local unsigned builds fall back to debug signing; CI release
                // builds always provide key.properties.
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            // 移除未使用的资源，进一步压缩体积。
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
