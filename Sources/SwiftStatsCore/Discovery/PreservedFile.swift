//
//  PreservedFile.swift
//  SwiftStatsCore
//
//  A file in the user's package as it was before a command SwiftStats runs
//  there might change it (M5: the coverage build resolves dependencies in
//  the package root and writes `Package.resolved`), to be put back
//  afterwards: its exact bytes, or that it didn't exist. `ScratchRegistry`
//  puts it back when the command is interrupted.
//

import Foundation

/// A file's contents before a command, kept to be put back.
struct PreservedFile: Sendable {
    /// The file.
    let url: URL
    /// Its bytes; nil when it didn't exist.
    let contents: Data?

    /// The file at `url` as it is now; throws when it exists but can't be
    /// read, since it then couldn't be put back.
    init(url: URL) throws {
        self.url = url
        contents = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    /// Puts the file back as it was: its bytes written again when they
    /// changed, or the file removed when it didn't exist.
    func restore() throws {
        let fileManager = FileManager.default
        guard let contents else {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }
        if (try? Data(contentsOf: url)) != contents {
            try contents.write(to: url)
        }
    }
}
