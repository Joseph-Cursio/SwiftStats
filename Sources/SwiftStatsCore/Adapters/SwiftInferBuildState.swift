//
//  SwiftInferBuildState.swift
//  SwiftStatsCore
//
//  The SwiftEffectInference revision `swift-infer` was built with (PRD
//  §7.11), which its version string doesn't say: read from the
//  `workspace-state.json` of the SwiftPM build directory holding the
//  binary. A resolve without a rebuild changes the file but not the
//  binary, so the revision is possibly stale.
//

import Foundation

/// Reads a SwiftPM build directory's resolved dependencies.
enum SwiftInferBuildState {
    /// The name of SwiftPM's build directory.
    private static let buildDirectoryName = ".build"
    /// SwiftEffectInference's package identity.
    private static let effectInference = "swifteffectinference"

    /// The SwiftEffectInference revision in the `workspace-state.json` of
    /// the nearest `.build` above `executable`, at
    /// `object.dependencies[packageRef.identity].state.checkoutState.revision`;
    /// nil when there is none, or it names no checkout of the package.
    static func effectInferenceRevision(of executable: URL) -> String? {
        let components = executable.resolvingSymlinksInPath().deletingLastPathComponent().pathComponents
        guard let buildIndex = components.lastIndex(of: buildDirectoryName), buildIndex > 0 else {
            return nil
        }
        let build = URL(fileURLWithPath: "/" + components[1...buildIndex].joined(separator: "/"), isDirectory: true)
        guard let data = try? Data(contentsOf: build.appendingPathComponent("workspace-state.json")),
              let state = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let dependencies)? = member(state, ["object", "dependencies"]) else {
            return nil
        }
        for dependency in dependencies {
            guard case .string(effectInference)? = member(dependency, ["packageRef", "identity"]) else {
                continue
            }
            guard case .string(let revision)? = member(dependency, ["state", "checkoutState", "revision"]) else {
                return nil
            }
            return revision
        }
        return nil
    }

    /// The value at `path` of object keys under `value`; nil when one is missing.
    private static func member(_ value: JSONValue, _ path: [String]) -> JSONValue? {
        var current = value
        for key in path {
            guard case .object(let members) = current, let next = members[key] else {
                return nil
            }
            current = next
        }
        return current
    }
}
