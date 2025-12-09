// File: android/build.gradle.kts

import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory
import com.android.build.gradle.LibraryExtension

plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") apply false
}


allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

// Workaround: some third-party plugins don't declare an Android namespace.
// AGP 8+ requires a namespace in every Android library module.
// Set it here for legacy plugins so the build doesn't fail.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            when (project.name) {
                "jitsi_meet" -> namespace = "com.gunschu.jitsi_meet"
                "jitsi_meet_wrapper" -> namespace = "dev.saibotma.jitsi_meet_wrapper"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
