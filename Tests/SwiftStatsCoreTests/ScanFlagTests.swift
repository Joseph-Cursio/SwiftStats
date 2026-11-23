@testable import SwiftStatsCore
import Testing

/// What `scan`'s opt-in flags ask for (M5, M6, design §1): `--coverage`,
/// `--mutation` with `--since <rev>` or `--resume`, which need
/// `--mutation`, exclude each other and read the store, and the drop flags
/// `scan` and `diff` share.
@Suite("Scan flags")
struct ScanFlagTests {
    /// One combination of `scan`'s flags.
    struct Flags: Sendable, CustomTestStringConvertible {
        /// `--coverage`.
        let coverage: Bool
        /// `--mutation`.
        let mutation: Bool
        /// `--since <rev>`.
        let since: String?
        /// `--resume`.
        let resume: Bool
        /// False for `--no-store`.
        let storing: Bool

        /// The flags as a command line would spell them.
        var testDescription: String {
            [
                coverage ? "--coverage" : nil, mutation ? "--mutation" : nil, since.map { "--since \($0)" },
                resume ? "--resume" : nil, storing ? nil : "--no-store"
            ].compactMap(\.self).joined(separator: " ")
        }

        /// The tiers these flags ask for, or why they conflict.
        var tiers: Result<RequestedTiers, RequestedTiers.FlagConflict> {
            Result { () throws(RequestedTiers.FlagConflict) in
                try RequestedTiers.scanFlags(
                    coverage: coverage,
                    mutation: mutation,
                    since: since,
                    resume: resume,
                    storing: storing
                )
            }
        }
    }

    /// Flags that combine, and the tiers each gives.
    static let combining: [(Flags, RequestedTiers)] = [
        (Flags(coverage: false, mutation: false, since: nil, resume: false, storing: true), .syntaxOnly),
        (Flags(coverage: true, mutation: false, since: nil, resume: false, storing: false), .coverage),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: false, storing: false),
            RequestedTiers(mutation: .full)
        ),
        (
            Flags(coverage: true, mutation: true, since: "main", resume: false, storing: true),
            RequestedTiers(coverage: true, mutation: .since("main"))
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: true, storing: true),
            RequestedTiers(mutation: .resume)
        )
    ]

    /// Flags that conflict, and the usage error each gives.
    static let conflicting: [(Flags, String)] = [
        (
            Flags(coverage: false, mutation: false, since: "main", resume: false, storing: true),
            "--since needs --mutation"
        ),
        (
            Flags(coverage: true, mutation: false, since: nil, resume: true, storing: true),
            "--resume needs --mutation"
        ),
        (
            Flags(coverage: false, mutation: true, since: "main", resume: true, storing: true),
            "give --since or --resume, not both; a resume keeps the base of the run it continues"
        ),
        (
            Flags(coverage: false, mutation: true, since: "", resume: false, storing: true),
            "--since needs a commit, branch or tag"
        ),
        (
            Flags(coverage: false, mutation: true, since: "main", resume: false, storing: false),
            "--since reads the snapshot store, so it can't be used with --no-store"
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: true, storing: false),
            "--resume reads the snapshot store, so it can't be used with --no-store"
        )
    ]

    @Test("flags that combine ask for the tiers they name", arguments: combining)
    func accepted(_ flags: Flags, _ expected: RequestedTiers) throws {
        #expect(try flags.tiers.get() == expected)
    }

    @Test("flags that conflict are refused, saying why", arguments: conflicting)
    func refused(_ flags: Flags, _ message: String) {
        guard case .failure(let conflict) = flags.tiers else {
            Issue.record("\(flags.testDescription) should be refused")
            return
        }
        #expect(conflict.description == message)
    }

    @Test("--drop-coverage and --drop-mutation each drop only their own results")
    func dropOptions() {
        #expect(DropOptions(coverage: false, mutation: false).isEmpty)
        #expect(DropOptions(coverage: true, mutation: false) == .coverage)
        #expect(DropOptions(coverage: false, mutation: true) == .mutation)
        #expect(DropOptions(coverage: true, mutation: true) == [.coverage, .mutation])
    }
}
