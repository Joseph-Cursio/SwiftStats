//
//  ResultsFileModel+State.swift
//  SwiftStatsCoreTests
//
//  The model's state while it reads a drafted results file line by line:
//  the readable sessions and the trees they record, the last readable
//  header, each key's winning line, the last readable `stopped` line, and
//  each line's label.
//

@testable import SwiftStatsCore

extension ResultsFileModel {
    /// A readable session: its number and the pool tree it records, nil
    /// when it records none.
    struct Session {
        /// Its number.
        let number: Int
        /// Its tree's index in the pool.
        let tree: Int?
    }

    /// The last readable header.
    struct LastHeader {
        /// Its tag.
        let tag: Int
        /// The pool indices of its not-covered entries.
        let notCovered: [Int]
        /// Its tree's index in the pool.
        let tree: Int?
    }

    /// The winning line of a key.
    struct Winner {
        /// Its tag.
        let tag: Int
        /// Its session.
        let session: Int
    }

    /// What the model has read so far.
    struct State {
        /// Each physical line's label so far.
        var labels: [Label] = []
        /// The readable sessions, in file order.
        private var sessions: [Session] = []
        /// The last readable header.
        private var lastHeader: LastHeader?
        /// Each key's winning line.
        private var winners: [MutantKey: Winner] = [:]
        /// The tag of the last readable `stopped` line.
        private var stopped: Int?

        /// The label of `line` of `draft`, taking in what it records;
        /// `unbroken` when a line break follows it.
        mutating func read(_ line: ResultsFileDraft.Line, in draft: ResultsFileDraft, unbroken: Bool) -> Label {
            switch line.draft {
            case .blank:
                return draft.crlf && unbroken ? .unreadable : .notCounted
            case .garbage:
                return .unreadable
            case .unknown:
                return .readable
            case let .header(header):
                return read(header, tag: line.tag)
            case let .mutant(mutant):
                return read(mutant, tag: line.tag, keys: draft.keys)
            case let .retired(session, indices, flaw):
                return retire(indices, session: session, flaw: flaw, keys: draft.keys)
            case let .control(session, flaw):
                return flaw.isReadable && hasSession(session) ? .readable : .unreadable
            case let .end(session, reason, flaw):
                let known = isKnown(reason, in: ResultsLineRenderer.endReasons)
                return flaw.isReadable && known && hasSession(session) ? .readable : .unreadable
            case let .stopped(flaw):
                guard flaw.isReadable else {
                    return .unreadable
                }
                stopped = line.tag
                return .readable
            }
        }

        /// The label of a `retired` line of `session` naming the pool keys
        /// `indices`, with `flaw`, dropping those keys when it reads.
        private mutating func retire(
            _ indices: [Int],
            session: Int,
            flaw: ResultsLineDraft.Flaw,
            keys: [MutantKey]
        ) -> Label {
            guard flaw.isReadable, hasSession(session) else {
                return .unreadable
            }
            for index in indices {
                winners.removeValue(forKey: ResultsLineObjects.key(at: index, in: keys))
            }
            return .readable
        }

        /// The label of the header `header`, tagged `tag`, opening its
        /// session when it reads.
        private mutating func read(_ header: ResultsLineDraft.HeaderDraft, tag: Int) -> Label {
            let trees = ResultsLineRenderer.trees.count
            guard header.flaw.isReadable, header.formatVersion <= newestFormatVersion,
                  treeReads(header.tree, poolSize: trees)
            else {
                return .unreadable
            }
            let tree = treeIndex(header.tree, poolSize: trees)
            sessions.append(Session(number: header.session, tree: tree))
            lastHeader = LastHeader(tag: tag, notCovered: header.listsNotCovered ? header.notCovered : [], tree: tree)
            return .readable
        }

        /// The label of the `mutant` line `mutant`, tagged `tag`, its key
        /// from `keys`, winning its key when it reads.
        private mutating func read(_ mutant: ResultsLineDraft.MutantDraft, tag: Int, keys: [MutantKey]) -> Label {
            guard mutant.flaw.isReadable, isKnown(mutant.outcome, in: ResultsLineRenderer.outcomes),
                  isKnown(mutant.ending, in: ResultsLineRenderer.endings), hasSession(mutant.session)
            else {
                return .unreadable
            }
            winners[ResultsLineObjects.key(at: mutant.key, in: keys)] = Winner(tag: tag, session: mutant.session)
            return .readable
        }

        /// What the file read reads as, its keys from `keys`.
        func expected(keys: [MutantKey]) -> Expected {
            guard let lastHeader else {
                let outcome: Outcome = stopped.map { .stopped(tag: $0) } ?? .noHeader
                return Expected(outcome: outcome, labels: labels, mutants: [:], tested: 0)
            }
            var mutants: [MutantKey: Mutant] = [:]
            for (key, winner) in winners {
                let snapshot = ResultsLineObjects.snapshot(winner.tag)
                mutants[key] = Mutant(
                    marker: ResultsLineObjects.marker(winner.tag),
                    session: winner.session,
                    notCoveredFileSHA256: nil,
                    before: snapshot.before,
                    after: snapshot.after
                )
            }
            let tree = lastHeader.tree.map { ResultsLineRenderer.trees[$0] } ?? [:]
            for index in lastHeader.notCovered {
                let key = ResultsLineObjects.key(at: index, in: keys)
                if mutants[key] == nil {
                    let snapshot = ResultsLineObjects.listedSnapshot(lastHeader.tag)
                    mutants[key] = Mutant(
                        marker: ResultsLineObjects.listedMarker(lastHeader.tag),
                        session: nil,
                        notCoveredFileSHA256: tree[key.path],
                        before: snapshot.before,
                        after: snapshot.after
                    )
                }
            }
            return Expected(outcome: .results, labels: labels, mutants: mutants, tested: winners.count)
        }

        /// Whether a readable session numbered `number` is above.
        private func hasSession(_ number: Int) -> Bool {
            sessions.contains { $0.number == number }
        }

        /// Whether a header recording `tree` reads as far as its tree goes:
        /// not when its `projectDelta` claims another tree than it makes,
        /// or its base is no readable session's tree above.
        private func treeReads(_ tree: ResultsLineDraft.TreeDraft, poolSize: Int) -> Bool {
            guard case let .delta(base, _, honest) = tree else {
                return true
            }
            return honest && sessions.contains { $0.tree == base % poolSize }
        }

        /// The pool index of the tree a readable header recording `tree`
        /// records; nil when it records none.
        private func treeIndex(_ tree: ResultsLineDraft.TreeDraft, poolSize: Int) -> Int? {
            switch tree {
            case .noTree:
                nil
            case let .whole(index):
                index % poolSize
            case let .delta(_, target, _):
                target % poolSize
            }
        }
    }
}
