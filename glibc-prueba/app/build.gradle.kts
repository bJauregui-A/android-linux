plugins {
    id("com.android.application")
}

val sessionLayerAssets = layout.buildDirectory.dir("generated/session-layer-assets").get().asFile
val packageSessionLayer = tasks.register<Exec>("packageSessionLayer") {
    val archive = sessionLayerAssets.resolve("session-layer.tgz")
    inputs.dir(file("../escritorios"))
    inputs.file(file("../apk/primer-arranque.sh"))
    inputs.file(file("../apk/paquetes-zsh.txt"))
    inputs.file(file("../apk/instalar-aur.sh"))
    inputs.file(file("../android/android-shm-limpiar"))
    inputs.file(file("../mesa-gl/firefox"))
    outputs.file(archive)
    doFirst { archive.parentFile.mkdirs() }
    commandLine("tar", "-czf", archive.absolutePath, "-C", file("..").absolutePath,
        "escritorios", "apk/primer-arranque.sh", "apk/paquetes-zsh.txt", "apk/instalar-aur.sh", "android/android-shm-limpiar",
        "mesa-gl/firefox")
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

    // Una sola variante; se conserva el sufijo .sdk36 para no cambiar el paquete instalado.
    flavorDimensions += "target"
    productFlavors {
        create("sdk36") {
            dimension = "target"
            applicationIdSuffix = ".sdk36"
            targetSdk = 36
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
        getByName("main").assets.srcDir(sessionLayerAssets)
        getByName("sdk36").assets.srcDir("../trabajo/assets-sdk36")
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

tasks.named("preBuild").configure { dependsOn(packageSessionLayer) }

// B23: no armar el APK con una capa.tgz más vieja que sus fuentes (apk/armar.sh sdk36 la rehace). Va en la mezcla de
// assets y no en preBuild para que las pruebas unitarias corran igual.
val revisarCapa = tasks.register<Exec>("revisarCapa") {
    commandLine(file("../apk/capa-al-dia.sh").absolutePath, file("../trabajo/assets-sdk36/capa.tgz").absolutePath)
}
tasks.matching { it.name.matches(Regex("mergeSdk36\\w*Assets")) }.configureEach { dependsOn(revisarCapa) }

dependencies {
    implementation("com.github.termux.termux-app:terminal-view:v0.118.3")
    testImplementation("junit:junit:4.13.2")
}
