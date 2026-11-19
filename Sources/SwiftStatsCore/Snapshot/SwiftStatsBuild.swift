//
//  SwiftStatsBuild.swift
//  SwiftStatsCore
//
//  SwiftStats' own build identity (PRD §6.2). The executable supplies it from
//  what BuildInfoPlugin embedded; SwiftStatsCore never derives it, so a
//  package using the library doesn't run the plugin.
//

/// Which build of SwiftStats made a snapshot.
public struct SwiftStatsBuild: Codable, Hashable, Sendable {
    /// The hash `diff` compares: of the build inputs, or of the executable
    /// when the build had no git.
    public let identity: String
    /// The commit and dirty flag, as a label; nil without git.
    public let label: String?

    /// A build identity and its label.
    public init(identity: String, label: String?) {
        self.identity = identity
        self.label = label
    }
}
