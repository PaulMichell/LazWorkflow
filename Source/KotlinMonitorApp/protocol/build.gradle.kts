/* JVM catalogue module (c) 2026 Michell Computing.

   No Android plugin and no Android UI dependency. JUnit runs on a JDK. */

plugins {
  alias(libs.plugins.kotlin.jvm)
}

plugins.withId("com.android.application") {
  throw GradleException("The protocol module must not apply the Android application plugin.")
}
plugins.withId("com.android.library") {
  throw GradleException("The protocol module must not apply the Android library plugin.")
}

kotlin {
  compilerOptions {
    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
  }
  // Backup copies sit beside the live sources and redeclare the same types.
  sourceSets.getByName("main").kotlin.exclude("**/Backup/**")
  sourceSets.getByName("test").kotlin.exclude("**/Backup/**")
}

java {
  sourceCompatibility = JavaVersion.VERSION_17
  targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
  implementation(libs.kotlinx.serialization.json)
  testImplementation(libs.junit)
}
