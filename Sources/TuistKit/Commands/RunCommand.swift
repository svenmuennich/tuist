import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct RunCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a target in the project",
            discussion: """
            Given an runnable scheme or target the run command builds & runs it.
            All arguments after the scheme or target are forwarded.
            """
        )
    }

    @Flag(help: "Force the generation of the project before running.")
    var generate: Bool = false

    @Flag(help: "When passed, it cleans the project before running.")
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project with the target or scheme to be run.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme."
    )
    var configuration: String?

    @Argument(help: "The scheme to be run.")
    var scheme: String

    @Argument(
        parsing: .unconditionalRemaining,
        help: "The arguments to pass to the runnable target during execution."
    )
    var arguments: [String] = []

    func run() throws {
        let absolutePath: AbsolutePath
        if let path = path {
            absolutePath = AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try RunService().run(
            schemeName: scheme,
            generate: generate,
            clean: clean,
            path: absolutePath,
            configuration: configuration,
            arguments: arguments
        )
    }
}
