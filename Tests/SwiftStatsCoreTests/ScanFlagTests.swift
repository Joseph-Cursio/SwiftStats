@testable import SwiftStatsCore
import Testing

/// What `scan`'s opt-in flags ask for (M5–M7): `--coverage`, `--mutation`
/// with `--since <rev>` or `--resume`, which need `--mutation`, exclude
/// each other and read the store, `--index`, which combines with every
/// other flag, and the drop flags `scan` and `diff` share.
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
        /// `--index`.
        let index: Bool
        /// False for `--no-store`.
        let storing: Bool

        /// The flags as a command line would spell them.
        var testDescription: String {
            [
                coverage ? "--coverage" : nil, mutation ? "--mutation" : nil, since.map { "--since \($0)" },
                resume ? "--resume" : nil, index ? "--index" : nil, storing ? nil : "--no-store"
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
                .asking(index: index)
            }
        }
    }

    /// Flags that combine, and the tiers each gives.
    static let combining: [(Flags, RequestedTiers)] = [
        (Flags(coverage: false, mutation: false, since: nil, resume: false, index: false, storing: true), .syntaxOnly),
        (Flags(coverage: true, mutation: false, since: nil, resume: false, index: false, storing: false), .coverage),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: false, index: false, storing: false),
            RequestedTiers(mutation: .full)
        ),
        (
            Flags(coverage: true, mutation: true, since: "main", resume: false, index: false, storing: true),
            RequestedTiers(coverage: true, mutation: .since("main"))
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: true, index: false, storing: true),
            RequestedTiers(mutation: .resume)
        ),
        (
            Flags(coverage: false, mutation: false, since: nil, resume: false, index: true, storing: true),
            RequestedTiers(index: true)
        ),
        (
            Flags(coverage: false, mutation: false, since: nil, resume: false, index: true, storing: false),
            RequestedTiers(index: true)
        ),
        (
            Flags(coverage: true, mutation: false, since: nil, resume: false, index: true, storing: true),
            RequestedTiers(coverage: true, index: true)
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: false, index: true, storing: false),
            RequestedTiers(mutation: .full, index: true)
        ),
        (
            Flags(coverage: true, mutation: true, since: "main", resume: false, index: true, storing: true),
            RequestedTiers(coverage: true, mutation: .since("main"), index: true)
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: true, index: true, storing: true),
            RequestedTiers(mutation: .resume, index: true)
        )
    ]

    /// Flags that conflict, and the usage error each gives.
    static let conflicting: [(Flags, String)] = [
        (
            Flags(coverage: false, mutation: false, since: "main", resume: false, index: false, storing: true),
            "--since needs --mutation"
        ),
        (
            Flags(coverage: true, mutation: false, since: nil, resume: true, index: false, storing: true),
            "--resume needs --mutation"
        ),
        (
            Flags(coverage: false, mutation: true, since: "main", resume: true, index: false, storing: true),
            "give --since or --resume, not both; a resume keeps the base of the run it continues"
        ),
        (
            Flags(coverage: false, mutation: true, since: "", resume: false, index: false, storing: true),
            "--since needs a commit, branch or tag"
        ),
        (
            Flags(coverage: false, mutation: true, since: "main", resume: false, index: false, storing: false),
            "--since reads the snapshot store, so it can't be used with --no-store"
        ),
        (
            Flags(coverage: false, mutation: true, since: nil, resume: true, index: false, storing: false),
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

    @Test("--drop-coverage, --drop-mutation and --drop-index each drop only their own results")
    func dropOptions() {
        #expect(DropOptions(coverage: false, mutation: false, index: false).isEmpty)
        #expect(DropOptions(coverage: true, mutation: false, index: false) == .coverage)
        #expect(DropOptions(coverage: false, mutation: true, index: false) == .mutation)
        #expect(DropOptions(coverage: false, mutation: false, index: true) == .index)
        #expect(DropOptions(coverage: true, mutation: true, index: true) == [.coverage, .mutation, .index])
    }

    @Test("an --index request survives the mutation step's choice of base")
    func indexSurvivesMerging() throws {
        let flags = Flags(coverage: true, mutation: true, since: "main", resume: false, index: true, storing: true)
        let merged = try flags.tiers.get().merging(with: nil)

        #expect(merged == RequestedTiers(coverage: true, mutation: .since("main"), index: true))
    }
}
