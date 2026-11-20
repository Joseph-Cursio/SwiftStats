import Foundation

/// Strict body inference: a callee's own body beats a guess from its name.
final class Ledger {
    let cache = TotalsCache()
    let rows = RowStore()
    let totalsKey = "totals"

    // `upsert` is idempotent by name.
    func updateTotals() {
        cache.upsert(totalsKey)
    }

    // On the first pass `updateTotals()` is guessed non_idempotent from the
    // `update` prefix; from the second, its body's idempotent tier wins.
    func refresh() {
        updateTotals()
    }

    // Two hops from the anchor.
    func syncAll() {
        refresh()
    }

    // `print` refutes purity, so the tier comes from the body.
    func record(_ amount: Int) {
        print(amount)
        rows.insertRow(amount)
    }

    // Pure, though its body calls `insertRow`.
    func stage(_ amount: Int) -> Int {
        rows.insertRow(amount)
        return amount
    }

    // Refuted, and no callee resolves: no tier at all.
    func stamp() -> Date {
        Date()
    }

    // A callee another declaration annotates: declared-anchored.
    func flush(_ draft: Draft) {
        draft.persist()
    }
}
