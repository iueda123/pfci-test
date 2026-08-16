plugins {
    application
    id("org.openjfx.javafxplugin") version "0.1.0"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

javafx {
    version = "25.0.4"
    modules("javafx.controls", "javafx.swing")
}

application {
    mainClass = "dev.pfcitest.app.ContinuousImprovementApp"
    applicationDefaultJvmArgs = listOf("--enable-native-access=javafx.graphics")
}

dependencies {
    // The reporting SDK brings dev.continuousimprovement:core with it (api dependency).
    implementation("dev.continuousimprovement:reporting:0.1.0-SNAPSHOT")

    testImplementation(platform("org.junit:junit-bom:5.13.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
