/* Android application coordinates (c) 2026 Michell Computing.

   The TLS session and encrypted host store live here. Screens are separate.
   This module depends on the JVM protocol catalogue, not on Lazarus. */

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.android)
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
  testImplementation(libs.junit)
}
