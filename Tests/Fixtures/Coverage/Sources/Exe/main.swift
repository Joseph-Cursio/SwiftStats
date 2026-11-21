let computed = exeHelper(2)
print(computed)
/// Triples `value`; the tests run it, never the top-level code.
func exeHelper(_ value: Int) -> Int {
    value * 3
}
let mapped = [1, 2].map { $0 + computed }
print(mapped)
