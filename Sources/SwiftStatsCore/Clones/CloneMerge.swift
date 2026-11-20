//
//  CloneMerge.swift
//  SwiftStatsCore
//
//  SwiftCloneDetector's own merge of its passes (`CloneClass.merged`,
//  which `--all` applies), re-implemented over the separate runs so each
//  class keeps its pass (PRD §7.12). Classes are taken by mass, largest
//  first, then the pass making the stronger claim (subtree, sequence,
//  near-miss), then the earliest copy; a class is dropped when every copy
//  lies within the lines a kept class of the same or a stronger pass
//  already claimed in that file. A subtree class is exact when its copies
//  are exactly those of a `--type1` class.
//

/// Merges the passes' classes.
enum CloneMerge {
    /// A range of lines a kept class claimed, and how precisely.
    private struct Claim {
        /// First line.
        let start: Int
        /// Last line.
        let end: Int
        /// The claiming pass's specificity.
        let specificity: Int
    }

    /// The classes of `outputs`' subtree, sequence and near-miss runs,
    /// merged in the tool's report order, subtree classes marked exact
    /// against the `--type1` run.
    static func merged(_ outputs: [CloneDetectorPass: CloneDetectorOutput]) -> [PassClone] {
        let exactSets = Set((outputs[.type1]?.clones ?? []).map { Set($0.instances) })
        let tagged = CloneDetectorPass.runOrder.flatMap { pass -> [PassClone] in
            guard let classPass = pass.classPass else {
                return []
            }
            return (outputs[pass]?.clones ?? []).map { clone in
                var tagged = PassClone(pass: classPass, clone: clone)
                tagged.exact = classPass == .subtree && exactSets.contains(tagged.instanceSet)
                return tagged
            }
        }
        return merged(tagged)
    }

    /// `classes` in the tool's merged order, those whose every copy lies in
    /// lines already claimed by a class at least as specific dropped.
    static func merged(_ classes: [PassClone]) -> [PassClone] {
        var claimed: [String: [Claim]] = [:]
        var kept: [PassClone] = []
        for candidate in classes.sorted(by: mergeOrder) {
            let specificity = candidate.pass.specificity
            let isCovered = candidate.clone.instances.allSatisfy { instance in
                (claimed[instance.path] ?? []).contains { claim in
                    instance.startLine >= claim.start && instance.endLine <= claim.end
                        && claim.specificity <= specificity
                }
            }
            guard isCovered == false else {
                continue
            }
            for instance in candidate.clone.instances {
                claimed[instance.path, default: []].append(
                    Claim(start: instance.startLine, end: instance.endLine, specificity: specificity)
                )
            }
            kept.append(candidate)
        }
        return kept
    }

    /// The tool's merge order: mass descending, specificity ascending, then
    /// the earliest copy by path, start and end.
    private static func mergeOrder(_ lhs: PassClone, _ rhs: PassClone) -> Bool {
        if lhs.clone.mass != rhs.clone.mass {
            return lhs.clone.mass > rhs.clone.mass
        }
        if lhs.pass.specificity != rhs.pass.specificity {
            return lhs.pass.specificity < rhs.pass.specificity
        }
        switch (lhs.clone.instances.min(), rhs.clone.instances.min()) {
        case let (left?, right?):
            return left < right

        case (nil, _):
            return false

        case (_, nil):
            return true
        }
    }
}
