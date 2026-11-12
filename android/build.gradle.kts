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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Release contract with the Jenkins release pipeline:
//   ./gradlew updateVersion -PnewVersion=1.2.3 -PnewBuild=14
tasks.register("updateVersion") {
    group = "release"
    description = "Writes -PnewVersion / -PnewBuild into the Flutter project version files"
    val flutterRoot = rootProject.projectDir.parentFile
    val newVersion = providers.gradleProperty("newVersion")
    val newBuild = providers.gradleProperty("newBuild")
    doLast {
        val version = newVersion.orNull ?: throw GradleException("Missing -PnewVersion")
        val build = newBuild.orNull ?: throw GradleException("Missing -PnewBuild")
        if (!Regex("""\d+\.\d+\.\d+""").matches(version) || !Regex("""\d+""").matches(build)) {
            throw GradleException("Invalid version '$version' or build '$build'")
        }

        val pubspec = File(flutterRoot, "pubspec.yaml")
        pubspec.writeText(
            pubspec.readText().replace(Regex("(?m)^version:.*$"), "version: $version+$build")
        )
        println("Version updated to $version+$build")
    }
}
