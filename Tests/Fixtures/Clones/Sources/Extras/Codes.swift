/// A status code's label.
func label(for code: Int) -> String {
    switch code {
    case 200..<300:
        return "ok"
    case 300..<400:
        return "moved"
    case 400..<500:
        return "client error"
    default:
        return "server error"
    }
}

/// A status code's short label.
func shortLabel(for code: Int) -> String {
    switch code {
    case 200..<300:
        return "ok"
    case 300..<400:
        return "redirect"
    case 404:
        return "missing"
    case 400..<500:
        return "bad request"
    default:
        return "failure"
    }
}
