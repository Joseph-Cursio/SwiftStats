/// The perimeter of `square`: moved to Measure.swift in `after`, nested
/// function and all.
func perimeter(of square: Square) -> Int {
    func edges() -> Int {
        let count = 4
        return count
    }
    let total = edges() * square.side
    return total
}

/// A description: deleted in `after`.
func legacyDescription(of square: Square) -> String {
    let prefix = "Square of side "
    let text = prefix + String(square.side)
    return text
}
