pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Vista de terminal de Termux (solo el emulador, sin su entorno)
        maven("https://jitpack.io") { content { includeGroup("com.github.termux.termux-app") } }
    }
}

rootProject.name = "GlibcPrueba"
include(":app")
