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
    // Certains plugins compilent contre un SDK trop ancien pour leurs dépendances AndroidX.
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            compileSdk = 36
        }
    }
}
subprojects {
    // home_widget demande des versions « 2.+ » / « 1.+ » et compile en JVM 1.8 : les
    // dernières (work 2.12, coroutines 1.11, en JVM 11) cassent sa compilation.
    // Mêmes versions que la 2.7.18 (work 2.10 a fait planter la 2.8.0 au démarrage).
    // On fige des versions compatibles quand la version demandée est flottante.
    val pinned = mapOf(
        "androidx.work" to "2.9.0",
        "org.jetbrains.kotlinx" to "1.10.2",
        "androidx.glance" to "1.1.0",
    )
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            val v = pinned[requested.group]
            val floating = requested.version?.endsWith("+") == true
            val coroutines = requested.name.startsWith("kotlinx-coroutines")
            if (v != null && floating && (requested.group != "org.jetbrains.kotlinx" || coroutines)) useVersion(v)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
