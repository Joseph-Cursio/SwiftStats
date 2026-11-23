//
//  FileClone.swift
//  SwiftStatsCore
//
//  Copies single files for the mutation collector's copy (M6, design
//  §1.2): a regular file as an APFS clone where the volume allows, else as
//  a byte copy, its permissions kept; a symbolic link as a link with the
//  same target, never followed. Paths are looked at without following a
//  final link, so a link to a missing file still exists.
//

import Darwin
import Foundation

/// File copies and lookups that never follow a final symbolic link.
enum FileClone {
    /// Whether anything, a dangling link included, is at `url`.
    static func exists(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0
    }

    /// Whether `url` is a directory itself, not a link to one.
    static func isDirectory(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && status.st_mode & S_IFMT == S_IFDIR
    }

    /// Copies the file or link at `source` to `destination`, replacing
    /// what is there and making its folder.
    static func copy(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try remove(destination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: source.path) {
            try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
            return
        }
        // COPYFILE_CLONE clones when it can and copies otherwise, data,
        // permissions and dates alike.
        guard copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_CLONE)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Writes `data` to `destination` as a regular file, replacing what is
    /// there (a link too) and making its folder.
    static func write(_ data: Data, to destination: URL) throws {
        try remove(destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }

    /// Removes what is at `url`, if anything.
    static func remove(_ url: URL) throws {
        if exists(url) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Renames `source` to `destination`, replacing what is there; both on
    /// one volume.
    static func move(_ source: URL, to destination: URL) throws {
        try remove(destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
