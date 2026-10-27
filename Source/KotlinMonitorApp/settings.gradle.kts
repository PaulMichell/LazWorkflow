/* Gradle settings for KotlinMonitorApp (c) 2026 Michell Computing.

   The protocol module is plain JVM. The app module carries the Android
   coordinates and does not put Android types on the protocol classpath. */

pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "KotlinMonitorApp"
include(":protocol")
include(":app")
