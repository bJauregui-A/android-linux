plugins {
    id("com.android.application")
}

android {
    namespace = "dev.ben4shot.glibcprueba"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "dev.ben4shot.glibcprueba"
        minSdk = 30
        versionCode = 1
        versionName = "0.1"
        buildConfigField("boolean", "DIAGNOSTICO", "false")
        ndk { abiFilters += "arm64-v8a" }
        manifestPlaceholders["etiqueta"] = "Linux"
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
        // Igual a sdk36 pero aparte: para probar el APK autoinstalable desde cero sin tocar el Arch de la sdk36
        create("prueba") {
            dimension = "target"
            applicationIdSuffix = ".prueba"
            targetSdk = 36
            manifestPlaceholders["etiqueta"] = "Linux (prueba)"
        }
    }

    // Mismo applicationId y firma que sdk36Debug: instala como actualización para poder
    // reutilizar el Arch existente, pero al abrirlo barre los perfiles Wayland disponibles.
    buildTypes {
        getByName("debug") {
            buildConfigField("boolean", "DIAGNOSTICO", "false")
        }
        create("diagnostico") {
            initWith(getByName("debug"))
            manifestPlaceholders["etiqueta"] = "Linux diagnóstico"
            buildConfigField("boolean", "DIAGNOSTICO", "true")
            matchingFallbacks += listOf("debug")
        }
    }

    buildFeatures { buildConfig = true }

    // APK autoinstalable: assets de apk/armar.sh <variante> (base.tgz, capa.tgz, instalar.sh).
    // Sin comprimir: instalar.sh los lee directo del APK por offset (Instalador.java).
    sourceSets {
        for (v in listOf("sdk28", "sdk36", "prueba")) getByName(v).assets.srcDir("../trabajo/assets-$v")
    }
    androidResources {
        noCompress += "tgz"
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
