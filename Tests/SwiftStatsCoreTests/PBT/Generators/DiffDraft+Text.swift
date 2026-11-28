//
//  DiffDraft+Text.swift
//  SwiftStatsCoreTests
//
//  How a drafted diff is written, as git writes it with GitChanges'
//  arguments: per file a `diff --git` line, its extended headers (index,
//  modes, similarity, rename from and to), its old- and new-path lines
//  (`--- a/…`, `+++ b/…`, `/dev/null` for a missing side), then its hunks,
//  each a header and its changed lines, and git's note when the last line
//  has no newline. Headers and hunk headers end in LF; a changed line ends
//  in CR LF where its file's ending says so (design B5, U9). A path holding
//  a control byte, `"` or `\` is quoted with C escapes, git's letters
//  `\a \b \t \n \v \f \r \" \\` and octal for any other control
//  (core.quotepath off, so other bytes stay as they are, unless the file
//  writes its non-ASCII bytes as octal, as core.quotepath on would); a path
//  line whose name holds a space ends in a tab, as git writes it.
//

/// How a drafted diff is written.
extension DiffDraft {
    /// The byte git writes as `\a`.
    static let bell: UInt8 = 0x07
    /// The byte git writes as `\b`.
    static let backspace: UInt8 = 0x08
    /// The byte git writes as `\v`.
    static let verticalTab: UInt8 = 0x0B
    /// The byte git writes as `\f`.
    static let formFeed: UInt8 = 0x0C
    /// The first byte that isn't a control.
    static let firstPrintable: UInt8 = 0x20
    /// The delete control.
    static let delete: UInt8 = 0x7F
    /// The first byte past ASCII.
    static let firstNonASCII: UInt8 = 0x80
    /// The width of an octal escape (forced: git writes three digits).
    static let octalWidth = 3
    /// The radix of an octal escape (forced).
    static let octal = 8
    /// git's note after a last line with no newline.
    static let noNewline = "\\ No newline at end of file"

    /// The diff's lines, in order, each without its LF.
    var lines: [Line] {
        files.enumerated().flatMap { index, file in lines(of: file, at: index) }
    }

    /// The escape git writes for `byte`, the letter after `\`, when it has
    /// one.
    static func letter(for byte: UInt8) -> Character? {
        let letters: [UInt8: Character] = [
            bell: "a", backspace: "b", UInt8(ascii: "\t"): "t", UInt8(ascii: "\n"): "n", verticalTab: "v",
            formFeed: "f", UInt8(ascii: "\r"): "r", UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\"
        ]
        return letters[byte]
    }

    /// Whether git quotes a path holding `byte`: a control, `"` or `\`, and
    /// a byte past ASCII when `octalHigh`.
    static func needsQuoting(_ byte: UInt8, octalHigh: Bool) -> Bool {
        byte < firstPrintable || byte == delete || letter(for: byte) != nil || (octalHigh && byte >= firstNonASCII)
    }

    /// `name` as git writes it in a header: as it is, or quoted with C
    /// escapes when a byte needs it.
    static func quoted(_ name: String, octalHigh: Bool) -> String {
        let bytes = Array(name.utf8)
        guard bytes.contains(where: { needsQuoting($0, octalHigh: octalHigh) }) else {
            return name
        }
        var written: [UInt8] = [UInt8(ascii: "\"")]
        for byte in bytes {
            if let letter = letter(for: byte) {
                written += [UInt8(ascii: "\\")] + Array(String(letter).utf8)
            } else if needsQuoting(byte, octalHigh: octalHigh) {
                let digits = String(byte, radix: octal)
                written += Array(("\\" + String(repeating: "0", count: octalWidth - digits.count) + digits).utf8)
            } else {
                written.append(byte)
            }
        }
        written.append(UInt8(ascii: "\""))
        // Every byte copied as it is came from a String, so the bytes are
        // UTF-8, and none starts with a byte order mark: the quote does.
        return String(bytes: written, encoding: .utf8) ?? name
    }

    /// `name` as an old- or new-path line writes it: quoted when needed,
    /// then a tab when the written name holds a space.
    static func pathLine(_ name: String, octalHigh: Bool) -> String {
        let written = quoted(name, octalHigh: octalHigh)
        return written.contains(" ") ? written + "\t" : written
    }

    /// The lines of `file`, the file at `index`.
    func lines(of file: DiffFileDraft, at index: Int) -> [Line] {
        let old = oldPath(of: file)
        let new = newPath(of: file)
        let quote = { (name: String) in Self.quoted(name, octalHigh: file.octalHigh) }
        let aName = "a/" + (old ?? new ?? "")
        let bName = "b/" + (new ?? old ?? "")
        var text = ["diff --git \(quote(aName)) \(quote(bName))"]
        switch file.kind {
        case .added:
            text += ["new file mode 100644", "index 0000000..2222222"]

        case .changed:
            text += ["index 1111111..2222222 100644"]

        case .deleted:
            text += ["deleted file mode 100644", "index 1111111..0000000"]

        case .modeOnly:
            text += ["old mode 100644", "new mode 100755"]

        case .pureRename:
            text += ["similarity index 100%", "rename from \(quote(old ?? ""))", "rename to \(quote(new ?? ""))"]

        case .renamed:
            text += [
                "similarity index 87%", "rename from \(quote(old ?? ""))", "rename to \(quote(new ?? ""))",
                "index 1111111..2222222 100644"
            ]
        }
        if file.hasPathLines {
            text.append("--- " + (old.map { Self.pathLine("a/" + $0, octalHigh: file.octalHigh) } ?? Self.devNull))
            text.append("+++ " + (new.map { Self.pathLine("b/" + $0, octalHigh: file.octalHigh) } ?? Self.devNull))
        }
        var rendered = [Line(bytes: Array(text[0].utf8), role: .fileHeader(file: index))]
        rendered += text.dropFirst().map { Line(bytes: Array($0.utf8), role: .other) }
        rendered += changedLines(of: file, at: index)
        return rendered
    }

    /// The hunk headers and changed lines of `file`, the file at `index`,
    /// and git's no-newline note after the last changed line when the file
    /// asks for it.
    func changedLines(of file: DiffFileDraft, at index: Int) -> [Line] {
        var rendered: [Line] = []
        var changed = 0
        let onAddedFile = file.kind == .added
        for hunk in file.hunks {
            let header = Array(hunk.header(onAddedFile: onAddedFile).utf8)
            rendered.append(Line(bytes: header, role: .hunkHeader(file: index)))
            for bytes in hunk.lines(onAddedFile: onAddedFile) {
                let endsInCR = file.endsInCarriageReturn(at: changed)
                let role = Role.changed(file: index, endsInCR: endsInCR)
                rendered.append(Line(bytes: bytes + (endsInCR ? [UInt8(ascii: "\r")] : []), role: role))
                changed += 1
            }
        }
        if file.endsWithoutNewline, changed > 0 {
            rendered.append(Line(bytes: Array(Self.noNewline.utf8), role: .other))
        }
        return rendered
    }
}
