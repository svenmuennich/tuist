import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistSupport

protocol RunServicing {

    /// Runs the given scheme (or first runnable scheme).
    ///
    /// - Parameters:
    ///   - schemeName: The name of the scheme to run.
    ///   - generate: Whether to generate the project before running.
    ///   - clean: Whether to clean the project before running.
    ///   - path: The path of the project containing the runnable scheme.
    ///   - configuration: The configuration to use while building & running the project.
    ///   - arguments: The arguments tot pass to the runnable target on execution.
    func run(
        schemeName: String,
        generate: Bool,
        clean: Bool,
        path: AbsolutePath,
        configuration: String?,
        arguments: [String]
    ) throws
}

enum RunServiceError: FatalError {
    case workspaceNotFound(path: AbsolutePath)
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutRunnableTarget(scheme: String)
    case runnableNotFound(path: AbsolutePath)
    case featureNotImplemented

    var description: String {
        switch self {
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path.pathString)"
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutRunnableTarget(scheme):
            return "The scheme \(scheme) cannot be run because it contains no runnable target."
        case let .runnableNotFound(path):
            return "The runnable product was expected but not found at \(path.pathString)."
        case let .featureNotImplemented:
            return "Sorry, this feature is not currently implemented."
        }
    }

    var type: ErrorType {
        switch self {
        case .schemeNotFound,
             .workspaceNotFound,
             .runnableNotFound,
             .schemeWithoutRunnableTarget,
             .featureNotImplemented:
            return .abort
        }
    }
}

final class RunService: RunServicing {
    private let generator: Generating
    private let buildGraphInspector: BuildGraphInspecting
    private let buildService: BuildServicing
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating

    init(
        generator: Generating = Generator(contentHasher: CacheContentHasher()),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        buildService: BuildServicing = BuildService(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator()
    ) {
        self.generator = generator
        self.buildGraphInspector = buildGraphInspector
        self.buildService = buildService
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
    }

    func run(
        schemeName: String,
        generate: Bool,
        clean: Bool,
        path: AbsolutePath,
        configuration: String?,
        arguments: [String]
    ) throws {
        let graph: ValueGraph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try generator.generateWithGraph(path: path, projectOnly: false).1
        } else {
            graph = try generator.load(path: path)
        }
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let runnableSchemes = buildGraphInspector.runnableSchemes(graphTraverser: graphTraverser)
        guard let workspacePath = try buildGraphInspector.workspacePath(directory: path) else {
            throw RunServiceError.workspaceNotFound(path: path)
        }

        logger.log(level: .debug, "Found the following runnable schemes: \(runnableSchemes.map(\.name).joined(separator: ", "))")

        guard let scheme = runnableSchemes.first(where: { $0.name == schemeName }) else {
            throw RunServiceError.schemeNotFound(scheme: schemeName, existing: runnableSchemes.map(\.name))
        }

        guard let (project, runnableTarget) = buildGraphInspector.runnableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw RunServiceError.schemeWithoutRunnableTarget(scheme: scheme.name)
        }

        try buildService.buildScheme(
            scheme: scheme,
            graphTraverser: graphTraverser,
            workspacePath: workspacePath,
            clean: clean,
            configuration: configuration,
            buildOutputPath: nil
        )

        try runTarget(
            runnableTarget,
            project: project,
            workspacePath: workspacePath,
            configuration: configuration,
            arguments: arguments
        )
    }

    private func runTarget(
        _ target: Target,
        project: Project,
        workspacePath: AbsolutePath,
        configuration: String?,
        arguments: [String]
    ) throws {
        let configuration = configuration ?? project.settings.defaultDebugBuildConfiguration()?.name ?? BuildConfiguration.debug.name
        let xcodeBuildDirectory = try xcodeProjectBuildDirectoryLocator.locate(
            platform: target.platform,
            projectPath: workspacePath,
            configuration: configuration
        )

        let runnablePath = xcodeBuildDirectory.appending(component: target.productNameWithExtension)
        guard FileHandler.shared.exists(runnablePath) else {
            throw RunServiceError.runnableNotFound(path: runnablePath)
        }

        if target.product == .commandLineTool {
            logger.notice("Running executable \(runnablePath.basename)", metadata: .section)
            try runExecutable(runnablePath, arguments: arguments)
        } else {
            logger.notice("Running app \(target.productName)", metadata: .section)
            try runApp(runnablePath, platform: target.platform)
        }
    }

    private func runExecutable(_ executablePath: AbsolutePath, arguments: [String]) throws {
        logger.debug("Forwarding arguments: \(arguments.joined(separator: ", "))")
        try System.shared.runAndPrint([executablePath.pathString] + arguments)
    }

    private func runApp(_ appPath: AbsolutePath, platform: Platform) throws {
        throw RunServiceError.featureNotImplemented
    }
}
