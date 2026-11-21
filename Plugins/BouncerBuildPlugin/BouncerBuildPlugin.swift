import Foundation
import PackagePlugin

/// Runs `bouncer check` on a target's sources during every build that changes them, so Bouncer's findings
/// show up as compiler diagnostics in `swift build` and in Xcode's issue navigator.
@main
struct BouncerBuildPlugin: BuildToolPlugin {
    /// Creates the Bouncer build command for a SwiftPM target.
    ///
    /// - Parameters:
    ///   - context: The plugin context, which provides the bouncer tool and a work directory.
    ///   - target: The target being built.
    /// - Returns: One build command, or none for a target without sources Bouncer reads.
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let module = target.sourceModule else { return [] }
        let sources = module.sourceFiles.map(\.url).filter(BouncerCommandFactory.isAnalyzable)
        let factory = BouncerCommandFactory(
            tool: try context.tool(named: "bouncer").url, workDirectory: context.pluginWorkDirectoryURL,
            projectDirectory: context.package.directoryURL
        )
        return factory.commands(targetName: target.name, sources: sources)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension BouncerBuildPlugin: XcodeBuildToolPlugin {
    /// Creates the Bouncer build command for an Xcode project target.
    ///
    /// - Parameters:
    ///   - context: The Xcode plugin context, which provides the bouncer tool and a work directory.
    ///   - target: The Xcode target being built.
    /// - Returns: One build command, or none for a target without sources Bouncer reads.
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let sources = target.inputFiles.map(\.url).filter(BouncerCommandFactory.isAnalyzable)
        let factory = BouncerCommandFactory(
            tool: try context.tool(named: "bouncer").url, workDirectory: context.pluginWorkDirectoryURL,
            projectDirectory: context.xcodeProject.directoryURL
        )
        return factory.commands(targetName: target.displayName, sources: sources)
    }
}
#endif

/// Builds the one build command both plugin entry points share.
struct BouncerCommandFactory {
    /// Source extensions Bouncer analyzes; other inputs (resources, plists, asset catalogs) are left out.
    static let extensions: Set<String> = [
        "swift", "m", "mm", "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "js", "ts", "py", "sh",
    ]

    /// The bouncer executable inside the artifact bundle.
    let tool: URL
    /// The plugin's work directory, the only place a sandboxed build command may write.
    let workDirectory: URL
    /// The package or Xcode project directory, which bouncer runs from so it finds the repo and `.bouncer`.
    let projectDirectory: URL

    /// Whether Bouncer reads a file, judged by its extension.
    ///
    /// - Parameter url: The source file.
    /// - Returns: Whether to pass the file to `bouncer check`.
    static func isAnalyzable(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Builds the command that checks a target's sources and touches a stamp file when it passes.
    ///
    /// The command is a build command rather than a prebuild one, so it reruns only when a source file or a
    /// `.bouncer` config it reads has changed since the stamp was written.
    ///
    /// - Parameters:
    ///   - targetName: The target's name, for the build log and the stamp file's name.
    ///   - sources: The target's analyzable source files.
    /// - Returns: The build command, or none when there are no sources.
    func commands(targetName: String, sources: [URL]) -> [Command] {
        guard !sources.isEmpty else { return [] }
        let stamp = workDirectory.appendingPathComponent("\(targetName).bouncer-stamp")
        let arguments = ["-c", Self.wrapper, "bouncer-build", projectDirectory.path, stamp.path, tool.path]
            + ["check", "--format", "xcode", "--no-update-check", "--progress", "off", "--files"]
            + sources.map(\.path)
        return [.buildCommand(
            displayName: "Bouncer \(targetName)", executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: arguments, environment: ["BOUNCER_NO_UPDATE_CHECK": "1"],
            inputFiles: sources + configFiles(), outputFiles: [stamp]
        )]
    }

    /// The shell wrapper: runs bouncer from the project directory and writes the stamp only on success.
    ///
    /// A failing run leaves no stamp, so the next build runs it again instead of hiding the errors.
    static let wrapper = #"cd "$1" || exit 2; stamp=$2; shift 2; "$@" && : > "$stamp""#

    /// The repo's `.bouncer`, which bouncer reads from the enclosing git repository's root (or the project
    /// directory outside git), so editing the config reruns the check.
    ///
    /// - Returns: The config file, or nothing when the repo has none.
    func configFiles() -> [URL] {
        let config = repoRoot().appendingPathComponent(".bouncer")
        return FileManager.default.fileExists(atPath: config.path) ? [config] : []
    }

    /// Finds the git working tree root the project directory sits in, as bouncer itself does.
    ///
    /// - Returns: The nearest ancestor holding `.git`, or the project directory when there is none.
    func repoRoot() -> URL {
        var directory = projectDirectory.standardizedFileURL
        while !Self.isRepoRoot(directory) {
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return projectDirectory }
            directory = parent
        }
        return directory
    }

    /// Whether a directory is a git working tree's root.
    ///
    /// - Parameter directory: The directory to test.
    /// - Returns: Whether it holds a `.git` directory or file.
    static func isRepoRoot(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }
}
