import ArgumentParser

/// Output formats for `swiftstats report` and `swiftstats diff`.
enum ReportFormat: String, ExpressibleByArgument, CaseIterable {
    /// Deterministic JSON (PRD §9 output contract).
    case json
    /// GitHub-flavoured Markdown.
    case markdown
}
