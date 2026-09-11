// Codegen + round-trip prototype only — see
// docs/slices/06. Protobuf Codegen Prototype.spec.md. `com.squareup.wire`
// is a provisional pick for schema-lock-time verification, not the real
// Android app's library decision (Scope, Out, item 2 — deferred to
// roadmap step 12).

plugins {
    kotlin("jvm") version "2.4.20"
    id("com.squareup.wire") version "7.0.1"
}

repositories {
    mavenCentral()
}

wire {
    sourcePath {
        srcDir("..")
        include("buttons.proto")
    }
    kotlin {}
}

// Gradle 9's stricter task-validation flags an implicit ordering gap
// between the wire plugin's generateMainProtos and the standard
// processResources task. Declaring it explicitly is Gradle's own
// suggested fix (see the validation error's "Possible solutions"). Uses
// `matching` + `configureEach` rather than `named` — the wire plugin
// registers its task after this script body runs, so `named` fails with
// "task not found" at this point in configuration.
tasks.matching { it.name == "generateMainProtos" }.configureEach {
    dependsOn("processResources", "processTestResources")
}

dependencies {
    testImplementation(kotlin("test-junit"))
}
