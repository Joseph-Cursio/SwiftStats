//
//  EffectInferenceRevision.swift
//  SwiftStatsCore
//
//  The SwiftEffectInference revision SwiftStats links. The package has no
//  tags, so `Package.swift` pins it by revision; a test keeps this constant
//  equal to the revision in `Package.resolved`.
//

/// The linked SwiftEffectInference revision.
enum EffectInferenceRevision {
    /// The pinned commit, as `Package.swift` names it.
    static let pinned = "ba3624d754c3c9150c946f66468c2c356be3e7e0"

    /// The collector's build identity: the pinned commit.
    static var identity: String {
        "git:" + pinned
    }
}
