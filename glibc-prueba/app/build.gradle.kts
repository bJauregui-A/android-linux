plugins {
    id("com.android.application")
}

android {
    namespace = "dev.ben4shot.glibcprueba"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "dev.ben4shot.glibcprueba"
        minSdk = 31
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
    }

    // Anfitrión Wayland (necesita wayland/compilar.sh antes)
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Dos variantes para comparar las restricciones de ejecución (W^X) según targetSdk.
    flavorDimensions += "target"
    productFlavors {
        create("sdk28") {
            dimension = "target"
            applicationIdSuffix = ".sdk28"
            targetSdk = 28
        }
        create("sdk36") {
            dimension = "target"
            applicationIdSuffix = ".sdk36"
            targetSdk = 36
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Extraer jniLibs a nativeLibraryDir: es la única carpeta de la app que Android deja ejecutar.
    packaging {
        jniLibs.useLegacyPackaging = true
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

dependencies {
    implementation("com.github.termux.termux-app:terminal-view:v0.118.3")
}
