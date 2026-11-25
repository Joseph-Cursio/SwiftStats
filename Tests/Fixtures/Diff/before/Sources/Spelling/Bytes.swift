import Foundation

/// The size of `value`, `Foundation.Data` here: its key is the one in
/// Words.swift, where `Data` is `Glossary.Data`, so both keys get their file
/// (a collision the USR separates). Moved to ByteSize.swift in `after`.
func size(of value: Data) -> Int {
    value.count
}
