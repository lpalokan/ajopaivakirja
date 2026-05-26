pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        // Google-hosted Maven Central GCS mirror, kept as a fallback for the
        // periodic 403 throttling that repo.maven.apache.org returns to CI
        // IP ranges. Gradle tries each repo in order, so this only kicks in
        // when the primary fails.
        maven {
            name = "MavenCentralGcsMirror"
            url = uri("https://maven-central.storage.googleapis.com/maven2/")
        }
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
