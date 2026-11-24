// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// The Bouncer release this package's binary comes from. Bumped, with `bouncerChecksum`, after every
/// Bouncer release; see README.md's "Releasing" section.
let bouncerVersion = "v1.3.0"

/// The SHA-256 of that release's `bouncer.artifactbundle.zip`, as printed by the release workflow.
let bouncerChecksum = "c96640dff392923886141b988457d47afebb8d35bb6bfb986a5a44d3c63ceb95"

/// Builds the binary target: the release asset, or a local bundle when `BOUNCER_PLUGIN_LOCAL_BUNDLE` is set.
///
/// The local form is for testing an unreleased Bouncer. Set the variable to a `bouncer.artifactbundle`
/// directory or `.zip` inside this package (SwiftPM requires binary targets to live in the package), such as
/// `LocalBundle/bouncer.artifactbundle.zip`, which .gitignore keeps out of commits.
func bouncerBinary() -> Target {
    if let local = ProcessInfo.processInfo.environment["BOUNCER_PLUGIN_LOCAL_BUNDLE"], !local.isEmpty {
        return .binaryTarget(name: "BouncerBinary", path: local)
    }
    return .binaryTarget(
        name: "BouncerBinary",
        url: "https://github.com/matthewa26/bouncer/releases/download/\(bouncerVersion)/bouncer.artifactbundle.zip",
        checksum: bouncerChecksum
    )
}

let package = Package(
    name: "BouncerPlugin",
    products: [
        .plugin(name: "BouncerBuildPlugin", targets: ["BouncerBuildPlugin"]),
        .plugin(name: "BouncerCommandPlugin", targets: ["BouncerCommandPlugin"]),
    ],
    targets: [
        bouncerBinary(),
        .plugin(
            name: "BouncerBuildPlugin",
            capability: .buildTool(),
            dependencies: ["BouncerBinary"]
        ),
        .plugin(
            name: "BouncerCommandPlugin",
            capability: .command(
                intent: .custom(verb: "bouncer", description: "Run Bouncer's full review on this package."),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Bouncer caches per-file facts in .bouncer-cache/ at the repo root."
                    ),
                ]
            ),
            dependencies: ["BouncerBinary"]
        ),
    ]
)
