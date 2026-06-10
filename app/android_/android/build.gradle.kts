allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_blue_plus 1.34.x ships with compileSdk 33, but current AndroidX
// dependencies require 34+. Force a newer compileSdk on all plugin modules.
subprojects {
    fun forceCompileSdk() {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.compileSdkVersion(36)
    }
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
