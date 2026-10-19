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
    afterEvaluate {
        if (hasProperty("android")) {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val compileSdkMethod = androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    compileSdkMethod.invoke(androidExt, 36)
                } catch (_: Exception) {}
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
