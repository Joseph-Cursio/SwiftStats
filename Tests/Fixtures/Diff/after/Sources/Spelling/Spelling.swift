/// A length: retargeted from `Int` to `Double` in `after`.
typealias Length = Double

/// The sum of `values`: its parameter is spelled `[Int]` in `before` and
/// `Array<Int>` in `after`, one declaration to the compiler.
func total(of values: Array<Int>) -> Int {
    values.reduce(0, +)
}

/// Twice `length`: the same key in both trees, but another declaration in
/// `after`, where `Length` is retargeted.
func doubled(_ length: Length) -> Length {
    length + length
}
