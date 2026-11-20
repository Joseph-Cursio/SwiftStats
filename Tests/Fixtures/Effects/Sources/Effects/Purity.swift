import Foundation

enum ParseError: Error {
    case bad
}

// Throws its own error and has no `try`: pure_but_partial.
func parse(_ text: String) throws -> Int {
    guard let value = Int(text) else {
        throw ParseError.bad
    }
    return value
}

// Propagates a callee's error: refuted.
func parseTwice(_ text: String) throws -> Int {
    try parse(text) + 1
}

struct Grid {
    var cells: [Int]

    var count: Int {
        cells.count
    }

    /// @lint.effect idempotent
    var checksum: Int {
        cells.reduce(0, +)
    }

    var first: Int {
        get { cells[0] }
        set { cells[0] = newValue }
    }

    init(cells: [Int]) {
        self.cells = cells
    }

    subscript(index: Int) -> Int {
        cells[index]
    }
}

final class Handle {
    deinit {
        print("closed")
    }
}

// Constructing it reads the clock, which refutes every function that does.
struct Receipt {
    let issued = Date()
}

func makeReceipt() -> Receipt {
    Receipt()
}

// A default argument reads the clock.
func stamped(at date: Date = Date()) -> Date {
    date
}
