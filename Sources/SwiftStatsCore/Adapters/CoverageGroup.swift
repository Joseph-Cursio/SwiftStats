//
//  CoverageGroup.swift
//  SwiftStatsCore
//
//  The profiles of a coverage run that share a signature (M5): one test
//  bundle's XCTest and Swift Testing processes, and any exit-test children,
//  with the entry counts of their merged profile.
//

/// One signature's profiles and their function entry counts.
struct CoverageGroup: Sendable {
    /// The signature the profiles share.
    let signature: String
    /// The profiles, sorted by file name.
    let profiles: [CoverageProfile]
    /// The entry count of each function its non-empty profiles ran, by
    /// normalised mangled name (`ProfileShow`); a function missing ran 0
    /// times. Empty when every profile is empty.
    let counts: [String: Int64]

    /// The profiles that hold data.
    var written: [CoverageProfile] {
        profiles.filter { $0.isEmpty == false }
    }

    /// The names of the functions it ran at least once, sorted.
    var counted: [String] {
        counts.filter { $0.value > 0 }.keys.sorted()
    }

    /// Whether a framework wrote more than one profile here: an exit test's
    /// child adds one, and so may a crash after it.
    var hasExtraProfiles: Bool {
        CoverageProfile.frameworks.contains { framework in
            profiles.count { $0.framework == framework } > 1
        }
    }

    /// Whether `framework`'s process wrote a non-empty profile.
    func wrote(_ framework: String) -> Bool {
        profiles.contains { $0.framework == framework && $0.isEmpty == false }
    }
}
