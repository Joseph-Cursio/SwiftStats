/// The fields of a header, one `key: value` per line.
func parseHeader(_ text: String) -> [String: String] {
    var fields: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            continue
        }
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        fields[key] = value
    }
    return fields
}

/// The fields of a footer, one `key=value` per line, comments skipped.
func parseFooter(_ text: String) -> [String: String] {
    var fields: [String: String] = [:]
    for line in text.split(separator: "\n") where line.hasPrefix("#") == false {
        let parts = line.split(separator: "=", maxSplits: 1)
        if parts.count != 2 {
            continue
        }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        if fields[key] == nil {
            fields[key] = value
        }
    }
    return fields
}
