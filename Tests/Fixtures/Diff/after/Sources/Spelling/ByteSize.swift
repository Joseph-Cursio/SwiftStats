import Foundation

/// The size of `value`, `Foundation.Data` here: its key is the one in
/// WordCount.swift, where `Data` is `Glossary.Data`, so both keys get their
/// file (a collision the USR separates). In Bytes.swift in `before`.
func size(of value: Data) -> Int {
    value.count
}
