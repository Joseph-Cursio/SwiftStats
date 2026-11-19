/// Measurements of shapes.
enum Measure {
    /// The unit name.
    static let unit = "cm"
}

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
