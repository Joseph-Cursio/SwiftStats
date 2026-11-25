import Foundation

/// The fields of `line`: public, but `index-support` is in no library
/// product, and only tests call it.
public func parseLine(_ line: String) -> [String] {
    line.split(separator: ",").map(String.init)
}

/// The banner `IndexApp` prints.
public func banner() -> String {
    "\(recordName()) \(samePair())"
}

/// A `Codable` record whose `note` is decoded and never read.
struct Record: Codable {
    /// The name, read.
    let name: String
    /// The note, decoded and never read.
    let note: String
}

/// An `Equatable` pair whose properties only the synthesized `==` reads.
struct Pair: Equatable {
    /// The left value.
    let left: Int
    /// The right value.
    let right: Int
}

/// The name of a decoded record.
func recordName() -> String {
    let json = Data(#"{"name": "index", "note": "unread"}"#.utf8)
    return (try? JSONDecoder().decode(Record.self, from: json))?.name ?? ""
}

/// Whether two equal pairs compare equal.
func samePair() -> Bool {
    Pair(left: 1, right: 2) == Pair(left: 1, right: 2)
}
