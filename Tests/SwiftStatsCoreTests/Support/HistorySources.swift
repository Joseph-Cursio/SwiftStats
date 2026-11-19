/// Source text the history tests commit.
enum HistorySources {
    /// The function `area` with no extra line and no parameters.
    static func area() -> String {
        area("area", extra: "", parameters: "")
    }

    /// The function `area` with an extra line in its body.
    static func area(extra: String) -> String {
        area("area", extra: extra, parameters: "")
    }

    /// The function `area` with an extra line and parameters.
    static func area(extra: String, parameters: String) -> String {
        area("area", extra: extra, parameters: parameters)
    }

    /// The function `name` with an extra line in its body.
    static func area(_ name: String, extra: String) -> String {
        area(name, extra: extra, parameters: "")
    }

    /// A function whose body has three distinct lines.
    static func area(_ name: String, extra: String, parameters: String) -> String {
        """
        public struct Shape {
            public func \(name)(\(parameters)) -> Int {
                let width = 3
                let height = 4
                \(extra)return width * height
            }
        }

        """
    }
}
