import Glossary

/// The size of `value`, `Glossary.Data` here: its key is the one in
/// ByteSize.swift, where `Data` is `Foundation.Data`, so both keys get their
/// file (a collision the USR separates). In Words.swift in `before`.
func size(of value: Data) -> Int {
    value.words.count
}
