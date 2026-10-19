/* Android application coordinates (c) 2026 Michell Computing.

   Compose Material 3 screens and the TLS session live here.
   This module depends on the JVM protocol catalogue, not on Lazarus. */

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.android)
  alias(libs.plugins.kotlin.compose)
}

android {
  namespace = "computing.michell.monitor"
  compileSdk = libs.versions.compileSdk.get().toInt()

  defaultConfig {
    applicationId = libs.versions.applicationId.get()
    minSdk = libs.versions.minSdk.get().toInt()
    targetSdk = libs.versions.targetSdk.get().toInt()
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  buildFeatures {
    compose = true
  }
}

kotlin {
  compilerOptions {
    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
  }
}

dependencies {
  implementation(project(":protocol"))
  implementation(libs.kotlinx.coroutines.android)
  implementation(libs.security.crypto)
  implementation(platform(libs.compose.bom))
  implementation(libs.compose.ui)
  implementation(libs.compose.material3)
  implementation(libs.compose.ui.tooling.preview)
  debugImplementation(libs.compose.ui.tooling)
  implementation(libs.activity.compose)
  implementation(libs.lifecycle.viewmodel.ktx)
  implementation(libs.lifecycle.viewmodel.compose)
  testImplementation(libs.junit)
}
