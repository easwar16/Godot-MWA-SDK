plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "SolanaMWA"
val pluginPackageName = "com.solana.mwa.godot"

android {
    namespace = pluginPackageName
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34

        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = false
    }
}

dependencies {
    // Godot library
    compileOnly(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar", "*.aar"))))

    // MWA 2.0
    implementation("com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.3")

    // AndroidX
    implementation("androidx.activity:activity-ktx:1.8.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // JSON
    implementation("org.json:json:20231013")
}
