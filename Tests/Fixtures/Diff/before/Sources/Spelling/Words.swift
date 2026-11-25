import Glossary

/// The size of `value`, `Glossary.Data` here: its key is the one in
/// Bytes.swift, where `Data` is `Foundation.Data`, so both keys get their file
/// (a collision the USR separates). Moved to WordCount.swift in `after`.
func size(of value: Data) -> Int {
    value.words.count
}
