allprojects {
    repositories {
        google()
        mavenCentral()
        // Google-hosted Maven Central GCS mirror — fallback for the 403
        // throttling that repo.maven.apache.org occasionally returns to CI
        // IP ranges. Gradle tries each repo in order, so this only kicks in
        // when the primary fails.
        maven {
            name = "MavenCentralGcsMirror"
            url = uri("https://maven-central.storage.googleapis.com/maven2/")
        }
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
