//
//  DiffDraft.swift
//  SwiftStatsCoreTests
//
//  P14.1's input: a zero-context diff as decisions, the package path the
//  reader is given, and how the diff's headers write that path (the same,
//  or in the other Unicode normalization form, which Swift strings compare
//  equal). Each file sits in a folder (`DiffFileDraft.Place`) and is named
//  by its number, so its old path is that folder's path and its own
//  components. The model (`expected`) is the design's sentence: each file
//  that has an old path in the package, and hunks to give, gives its
//  hunks' old sides under that path from the package, in order; a new
//  file, and a file outside the package, give none. The rendering
//  (`DiffDraft+Text`) writes the bytes git writes.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// A zero-context diff as decisions, and the package it is read for.
struct DiffDraft: Sendable, CustomTestStringConvertible {
    /// What one rendered line is.
    enum Role: Hashable, Sendable {
        /// A changed line of the file at this index, and whether it ends
        /// in CR before its LF.
        case changed(file: Int, endsInCR: Bool)
        /// The `diff --git` line starting the file at this index.
        case fileHeader(file: Int)
        /// A hunk header of the file at this index.
        case hunkHeader(file: Int)
        /// Any other line: an extended header, an old- or new-path line,
        /// git's no-newline note.
        case other
    }

    /// One rendered line: its bytes, without the LF ending it, and what
    /// it is.
    struct Line: Hashable, Sendable {
        /// The bytes, without the LF ending the line.
        let bytes: [UInt8]
        /// What the line is.
        let role: Role
    }

    /// The folder outside a package that isn't the repository.
    static let elsewhere = "Elsewhere/"
    /// What a sibling folder's name adds to the package's last component.
    static let siblingSuffix = "x"
    /// The folder a renamed file moves to, in the package.
    static let movedFolder = "Moved/"
    /// What git writes for a missing side's path.
    static let devNull = "/dev/null"

    /// The package's path from the repository's top, as the reader is
    /// given it; empty for a package at the top.
    let package: String
    /// The package's path as the diff's headers write it: `package`, or
    /// `package` in the other normalization form.
    let written: String
    /// The files, in the diff's order.
    let files: [DiffFileDraft]

    /// The hunks the reader should give, by path from the package: each
    /// file in the package that has hunks to give, its hunks' old sides in
    /// order.
    var expected: [String: [DiffHunk]] {
        var hunks: [String: [DiffHunk]] = [:]
        for file in files where file.givesHunks && file.hunks.isEmpty == false {
            if let key = key(of: file) {
                hunks[key, default: []] += file.hunks.map(\.expected)
            }
        }
        return hunks
    }

    /// The diff as git writes it: each line and an LF.
    var data: Data {
        Data(lines.flatMap { $0.bytes + [UInt8(ascii: "\n")] })
    }

    /// The package, how the headers write it, the diff as the reader
    /// decodes it, and what the reader should give, in ASCII.
    var testDescription: String {
        let shown = expected.sorted { $0.key < $1.key }.map { key, hunks in
            "\(key.debugDescription): " + hunks.map { "(\($0.start),\($0.count))" }.joined(separator: " ")
        }
        return PBTTrace.ascii(
            "package \(package.debugDescription), written \(written.debugDescription); diff "
                + GitChanges.text(of: data).debugDescription
                + "; expected [" + shown.joined(separator: ", ") + "]"
        )
    }

    /// The path of the folder `place` names, with a `/` after it unless it
    /// is the top, as the diff's headers write it; nil for a new file.
    func folder(_ place: DiffFileDraft.Place) -> String? {
        let parts = written.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map { String($0) }
        let top = { (path: String) in path.isEmpty ? "" : path + "/" }
        switch place {
        case .elsewhere:
            return Self.elsewhere

        case .inPackage:
            return top(written)

        case .newFile:
            return nil

        case .parent:
            return written.isEmpty ? "" : top(parts.dropLast().joined(separator: "/"))

        case .sibling:
            return written + Self.siblingSuffix + "/"
        }
    }

    /// The old path of `file` from the repository's top, as the headers
    /// write it; nil for a new file.
    func oldPath(of file: DiffFileDraft) -> String? {
        folder(file.place).map { $0 + file.relative }
    }

    /// The new path of `file` from the repository's top; nil for a deleted
    /// file. A renamed file moves to `Moved/` in the package; an added file
    /// is in the package.
    func newPath(of file: DiffFileDraft) -> String? {
        let packageFolder = folder(.inPackage) ?? ""
        switch file.kind {
        case .added:
            return packageFolder + file.relative

        case .deleted:
            return nil

        case .pureRename, .renamed:
            return packageFolder + Self.movedFolder + (file.components.last ?? "")

        case .changed, .modeOnly:
            return oldPath(of: file)
        }
    }

    /// Whether `file`'s old path lies in the package: every old path does
    /// when the package is the repository, and otherwise only one in the
    /// package's own folder (the drafted folder names never spell the
    /// package's components, so no other place lands in it).
    func isInPackage(_ file: DiffFileDraft) -> Bool {
        file.place != .newFile && (package.isEmpty || file.place == .inPackage)
    }

    /// The path `file`'s hunks are filed under, from the package, when its
    /// old path lies in the package; else nil.
    func key(of file: DiffFileDraft) -> String? {
        guard isInPackage(file) else {
            return nil
        }
        return package.isEmpty ? oldPath(of: file) : file.relative
    }
}
