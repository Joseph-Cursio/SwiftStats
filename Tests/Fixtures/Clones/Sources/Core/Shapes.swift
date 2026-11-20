/// A rectangle.
struct Rectangle {
    var width: Double
    var height: Double

    func describe() -> String {
        let area = width * height
        let perimeter = 2 * (width + height)
        return "area \(area), perimeter \(perimeter)"
    }
}
