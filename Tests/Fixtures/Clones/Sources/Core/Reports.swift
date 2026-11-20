/// The summary line of a month's orders.
func monthlyReport(orders: [Int], refunds: [Int]) -> String {
    var lines: [String] = []
    let gross = orders.reduce(0, +)
    let returned = refunds.reduce(0, +)
    let net = gross - returned
    if net < 0 {
        lines.append("loss of \(-net)")
    } else {
        lines.append("profit of \(net)")
    }
    for order in orders where order > 1_000 {
        lines.append("large order \(order)")
    }
    return lines.joined(separator: "\n")
}

/// The summary line of a year's orders.
func yearlyReport(orders: [Int], refunds: [Int]) -> String {
    var lines: [String] = []
    let gross = orders.reduce(0, +)
    let returned = refunds.reduce(0, +)
    let net = gross - returned
    if net < 0 {
        lines.append("loss of \(-net)")
    } else {
        lines.append("profit of \(net)")
    }
    for order in orders where order > 10_000 {
        lines.append("large order \(order)")
    }
    print(lines.count)
    return lines.joined(separator: "\n")
}
