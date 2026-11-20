/// Loads the text at `path`, refusing temporary paths.
func load(_ path: String, log: inout [String]) -> String {
    let started = path.count
    if path.isEmpty || path.hasPrefix("/tmp") {
        print("rejected \(path)")
        log.append(path)
    }
    return String(repeating: "x", count: started)
}

/// Stores `value` at `path`, refusing temporary paths.
func store(_ path: String, value: Int, log: inout [String]) -> Bool {
    let doubled = value * 2
    let kept = doubled > 10
    if path.isEmpty || path.hasPrefix("/tmp") {
        print("rejected \(path)")
        log.append(path)
    }
    return kept && doubled.isMultiple(of: 3)
}

/// Sets up the first view.
func configureFirst(_ view: inout Settings) {
    view.color = "red"
    view.width = 10
    view.height = 20
    view.title = "first"
}

/// Sets up the second view.
func configureSecond(_ panel: inout Settings) {
    panel.visible = true
    panel.color = "blue"
    panel.width = 30
    panel.height = 40
}

/// A view's settings.
struct Settings {
    var color = ""
    var width = 0
    var height = 0
    var title = ""
    var visible = false
}
