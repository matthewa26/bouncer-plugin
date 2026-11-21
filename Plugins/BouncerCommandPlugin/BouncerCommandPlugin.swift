import Foundation
import PackagePlugin

/// `swift package bouncer`: runs `bouncer review` on the package directory and prints the report.
///
/// Extra arguments are passed through to `bouncer review`, so `swift package bouncer --format table` works.
/// With no arguments it reviews the whole package directory.
@main
struct BouncerCommandPlugin: CommandPlugin {
    /// Reviews the package.
    ///
    /// - Parameters:
    ///   - context: The plugin context, which provides the bouncer tool.
    ///   - arguments: The arguments after `swift package bouncer`.
    /// - Throws: If bouncer can't be started.
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "bouncer").url
        try BouncerReview.run(tool: tool, directory: context.package.directoryURL, arguments: arguments)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension BouncerCommandPlugin: XcodeCommandPlugin {
    /// Reviews the Xcode project's directory, from Xcode's File > Packages (or the project's context menu).
    ///
    /// - Parameters:
    ///   - context: The Xcode plugin context, which provides the bouncer tool.
    ///   - arguments: The arguments Xcode passes, such as `--target` selections, which are ignored.
    /// - Throws: If bouncer can't be started.
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "bouncer").url
        try BouncerReview.run(tool: tool, directory: context.xcodeProject.directoryURL, arguments: [])
    }
}
#endif

/// Runs `bouncer review` and reports how it went.
enum BouncerReview {
    /// Runs bouncer from a directory, streaming its output, and marks the command failed on a non-zero exit.
    ///
    /// - Parameters:
    ///   - tool: The bouncer executable.
    ///   - directory: The package or project directory to review.
    ///   - arguments: Extra `review` arguments.
    /// - Throws: If the process can't be started.
    static func run(tool: URL, directory: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = tool
        process.currentDirectoryURL = directory
        process.arguments = ["review", directory.path, "--no-update-check"] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        Diagnostics.error("bouncer review exited with status \(process.terminationStatus)")
    }
}
