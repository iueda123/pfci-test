plugins {
    base
}

allprojects {
    group = "dev.pfcitest"
    version = "0.1.0-SNAPSHOT"

    repositories {
        mavenCentral()
        // The improvement platform (dev.continuousimprovement:reporting) is consumed as an artifact,
        // never as a source copy. See repository-split.md in platform-for-continuous-improvement.
        // mavenLocal covers offline development and dispatcher-warmed agent runs; GitHub Packages
        // covers CI. The registry is only declared when credentials are present, so an unauthenticated
        // build fails on a missing artifact instead of on a missing username.
        mavenLocal()
        val registryUser = providers.environmentVariable("GPR_USER")
            .orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
        val registryToken = providers.environmentVariable("GPR_TOKEN")
            .orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
        if (!registryUser.isNullOrBlank() && !registryToken.isNullOrBlank()) {
            maven {
                name = "GitHubPackages"
                url = uri("https://maven.pkg.github.com/iueda123/platform-for-continuous-improvement")
                credentials {
                    username = registryUser
                    password = registryToken
                }
            }
        }
    }
}

subprojects {
    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
        testLogging {
            events("failed", "skipped")
        }
    }
}
