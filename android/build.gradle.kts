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
// Align JVM targets across Java/Kotlin tasks in plugin subprojects; some
// plugins (e.g. file_picker) still declare older Kotlin targets.
subprojects {
    afterEvaluate {
        if (!project.hasProperty("android")) return@afterEvaluate
        val androidExtension = project.extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension
        androidExtension?.compileOptions?.let { opts ->
            opts.sourceCompatibility = JavaVersion.VERSION_17
            opts.targetCompatibility = JavaVersion.VERSION_17
        }
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions {
                    jvmTarget.set(
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                    )
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
