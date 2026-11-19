/// The diagonal of `square`: added in `after`.
func diagonal(of square: Square) -> Double {
    let side = Double(square.side)
    let squared = side * side * 2
    return squared.squareRoot()
}
