//
//  HeldSlot.swift
//  SwiftStatsCore
//
//  The stored snapshot a scan would replace, as the checks made before
//  its slow runs name it (M7, design §9.5): its id, how a refusal names
//  it, where the package stands in git and the held results the scan may
//  let go.
//

/// The snapshot a storing scan would replace, for its checks before the
/// slow runs.
struct HeldSlot {
    /// The snapshot's id.
    let id: Int64
    /// How a refusal names it.
    let name: String
    /// Where the package stands in git.
    let git: GitState
    /// The held results the scan may let go.
    let drop: DropOptions
}
