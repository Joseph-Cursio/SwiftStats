//
//  CoverageAttachments.swift
//  SwiftStatsCore
//
//  Gathers the coverage outside every record (M5, PRD §6.1): the code
//  regions of the entries attached to a type or a file, and then the
//  mapped lines of each kept file that no record spans, each credited to
//  the innermost type holding it, else to its file. Every mapped line
//  of a file then lies in some record's span or in exactly one
//  attachment. Records' line tallies don't sum to the file's lines: by
//  llvm-cov's per-function rule a line shared by one-line sibling
//  accessors, or by a record and a nested one on the same line, counts
//  once for each of them.
//

/// Coverage attached to types and files.
struct CoverageAttachments {
    /// What an attachment is keyed by.
    private struct Key: Hashable {
        /// `type` or `file`.
        let attachedTo: FindingTarget
        /// The type's owner text or the file's path.
        let owner: String
    }

    /// The attached regions by key, then by file.
    private var regions: [Key: [String: [CoverageRegion]]] = [:]

    /// Attaches `attached`, code regions of `file`, to what `target` and
    /// `owner` name; none attaches nothing.
    mutating func attach(_ attached: [CoverageRegion], in file: String, to target: FindingTarget, owner: String) {
        guard attached.isEmpty == false else {
            return
        }
        regions[Key(attachedTo: target, owner: owner), default: [:]][file, default: []] += attached
    }

    /// The attachments, with the lines of the `kept` files (`fileLines`)
    /// that no record of `placement` spans; by what they attach to, then
    /// owner.
    func attachments(
        fileLines: [String: [CoverageLineIterator.Line]],
        kept: [String],
        placement: CoveragePlacement
    ) -> [CoverageAttachment] {
        var lines: [Key: [CoverageLineIterator.Line]] = [:]
        for path in kept {
            let spanned = placement.records(in: path).reduce(into: Set<Int>()) { spans, record in
                spans.formUnion(placement.span(of: record))
            }
            for line in fileLines[path] ?? [] where spanned.contains(line.line) == false {
                let owner = placement.typeOwner(holding: line.line, in: path)
                let key = owner.map { Key(attachedTo: .type, owner: $0) } ?? Key(attachedTo: .file, owner: path)
                lines[key, default: []].append(line)
            }
        }
        return Set(regions.keys).union(lines.keys)
            .sorted { ($0.attachedTo.rawValue, $0.owner) < ($1.attachedTo.rawValue, $1.owner) }
            .map { key in
                let deduplicated = (regions[key] ?? [:]).values.flatMap(CoverageRecordLines.deduplicated)
                return CoverageAttachment(
                    owner: key.owner,
                    attachedTo: key.attachedTo,
                    lines: CoverageRecordLines.tally(of: lines[key] ?? []),
                    regions: CoverageRecordLines.tally(of: deduplicated)
                )
            }
    }
}
