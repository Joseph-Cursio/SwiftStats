//
//  MarkdownList.swift
//  SwiftStatsCore
//
//  A long list in M7's report sections (design §10.1): a table of at most
//  its first 50 rows, saying how many there are when there are more,
//  since the JSON lists them all.
//

/// A table that prints at most a fixed number of rows.
enum MarkdownList {
    /// The rows a list prints.
    static let limit = 50

    /// A table of `items` under `header`, one row each by `row`, cut to
    /// the first `limit` with a note saying so; `empty` alone when there
    /// are none.
    static func lines<Item>(
        _ items: [Item],
        header: [String],
        empty: String,
        row: (Item) -> [String]
    ) -> [String] {
        lines(items, limit: limit, header: header, empty: empty, row: row)
    }

    /// A table of `items` under `header`, one row each by `row`, cut to
    /// the first `limit` with a note saying so; `empty` alone when there
    /// are none.
    static func lines<Item>(
        _ items: [Item],
        limit: Int,
        header: [String],
        empty: String,
        row: (Item) -> [String]
    ) -> [String] {
        var table = MarkdownTable(header: header)
        table.rows = items.prefix(limit).map(row)
        var lines = table.lines(empty: empty)
        if items.count > limit {
            lines += ["", "(first \(limit) of \(items.count); the JSON lists all)"]
        }
        return lines
    }
}
