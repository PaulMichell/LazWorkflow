/* Empty plain-JVM module (c) 2026 Michell Computing.

   Catalogue 3 codecs were removed. Version 4 codecs land here.
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
}

java {
  sourceCompatibility = JavaVersion.VERSION_17
  targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
  testImplementation(libs.junit)
}
