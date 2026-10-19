/* Root build for KotlinMonitorApp (c) 2026 Michell Computing.

   Plugins are declared here and applied by the modules. This file does not
   reference Lazarus, lazbuild, or the Pascal packages. */

plugins {
  alias(libs.plugins.kotlin.jvm) apply false
  alias(libs.plugins.kotlin.android) apply false
  alias(libs.plugins.android.application) apply false
}
