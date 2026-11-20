/// A box seen from above.
struct Box {
    var depth: Double
    var length: Double

    func summary() -> String {
        let volume = depth * length
        let edge = 2 * (depth + length)
        return "volume \(volume), edge \(edge)"
    }
}
