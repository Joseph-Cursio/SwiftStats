import ArgumentParser

/// Output formats for `swiftstats scan`.
enum ScanFormat: String, ExpressibleByArgument, CaseIterable {
    /// Deterministic JSON (PRD §9 output contract).
    case json
}
