//
//  TypeCycles.swift
//  SwiftStatsCore
//
//  USR type cycles (M7, design §4.3): the strongly connected components of
//  two or more production types in the graph whose edge A → B says a
//  member of A references B or a member of B, found with Tarjan's
//  algorithm (iterative, so a deep graph can't overflow the stack). Each
//  component's members are ordered by identity, then USR; components are
//  numbered from 1, the largest first, then by their first member, so the
//  numbers don't depend on the order the graph was built in.
//

/// The USR type cycles of a graph over types.
struct TypeCycles {
    /// One frame of the search: a node and the next successor to try.
    private struct Frame {
        /// The node, by position.
        let node: Int
        /// The position in its successors of the next to try.
        var next: Int
    }

    /// The cycles, numbered from 1 in this order, each one's members by
    /// identity, then USR.
    let cycles: [[String]]
    /// Each member's cycle number, by USR.
    let numbers: [String: Int]

    /// The cycles of `edges` (each type's successors, by USR) among
    /// `nodes`, by USR, each type named by `identity`.
    init(nodes: [String], edges: [String: Set<String>], identity: (String) -> TypeIdentity) {
        let keys = Dictionary(nodes.map { ($0, identity($0).parts + [$0]) }) { first, _ in first }
        let order: (String, String) -> Bool = { lhs, rhs in
            CodePointOrder.precedes(keys[lhs] ?? [lhs], keys[rhs] ?? [rhs])
        }
        let sorted = Array(Set(nodes)).sorted(by: order)
        let position = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1, $0) })
        let successors = sorted.map { node in
            edges[node, default: []].compactMap { position[$0] }.sorted()
        }
        let components = Self.components(successors)
            .filter { $0.count > 1 }
            .map { $0.sorted().map { sorted[$0] } }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : order(lhs[0], rhs[0])
            }
        cycles = components
        var numbered: [String: Int] = [:]
        for (offset, members) in components.enumerated() {
            for member in members {
                numbered[member] = offset + 1
            }
        }
        numbers = numbered
    }

    /// The strongly connected components of the graph whose node at each
    /// position has `successors` (positions), each component's members by
    /// position (Tarjan, iterative).
    private static func components(_ successors: [[Int]]) -> [[Int]] {
        let unvisited = -1
        var indices = Array(repeating: unvisited, count: successors.count)
        var lows = Array(repeating: 0, count: successors.count)
        var onStack = Array(repeating: false, count: successors.count)
        var stack: [Int] = []
        var components: [[Int]] = []
        var counter = 0
        for start in successors.indices where indices[start] == unvisited {
            var work = [Frame(node: start, next: 0)]
            indices[start] = counter
            lows[start] = counter
            counter += 1
            stack.append(start)
            onStack[start] = true
            while let top = work.last {
                let node = top.node
                if top.next < successors[node].count {
                    let successor = successors[node][top.next]
                    work[work.count - 1].next += 1
                    if indices[successor] == unvisited {
                        indices[successor] = counter
                        lows[successor] = counter
                        counter += 1
                        stack.append(successor)
                        onStack[successor] = true
                        work.append(Frame(node: successor, next: 0))
                    } else if onStack[successor] {
                        lows[node] = min(lows[node], indices[successor])
                    }
                    continue
                }
                work.removeLast()
                if let parent = work.last {
                    lows[parent.node] = min(lows[parent.node], lows[node])
                }
                if lows[node] == indices[node] {
                    var component: [Int] = []
                    while let member = stack.popLast() {
                        onStack[member] = false
                        component.append(member)
                        if member == node {
                            break
                        }
                    }
                    components.append(component)
                }
            }
        }
        return components
    }
}
