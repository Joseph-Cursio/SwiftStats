@testable import SwiftStatsCore
import Testing

/// The risk markers SwiftStats finds itself (PRD §7.4).
@Suite("Risk markers")
struct RiskMarkerTests {
    @Test("each marker is found once, at its position, with its kind")
    func markers() {
        let source = """
        @MainActor
        final class Screen {
            var label: String!
            @MainActor func refresh(_ value: Int) {
                precondition(value > 0)
                Swift.precondition(value < 100, "too large")
                preconditionFailure("not counted here")
                Task { await work() }
                Task<Void, Never>(priority: .low) { }
                Task.detached { }
                let pointer = unsafe raw.baseAddress
                let handler: @MainActor () -> Void = { }
            }
        }
        """
        let markers = CollectorHarness.markers(source)

        #expect(markers.map(\.rule) == [
            "mainActorDeclaration", "implicitlyUnwrappedOptional", "mainActorDeclaration", "precondition",
            "precondition", "taskCreation", "taskCreation", "unsafeExpression"
        ])
        #expect(markers.map { $0.places[0].line } == [1, 3, 4, 5, 6, 8, 9, 11])
        #expect(markers.map { $0.places[0].column } == [1, 16, 5, 9, 9, 9, 9, 23])
        #expect(markers.filter { $0.kind == .defect }.map(\.rule) == ["implicitlyUnwrappedOptional"])
        #expect(markers.allSatisfy { $0.tool == "swiftstats" && $0.category == nil })
    }

    @Test("in a file of top-level code, a declaration between statements attaches to its type or the file")
    func topLevelAttachment() throws {
        let source = """
        print("start")
        struct Config {
            var name: String!
        }
        var global: Int!
        precondition(global == nil)
        """
        let package = try TemporaryPackage(["Sources/Lib/main.swift": source])
        defer { package.remove() }

        let report = try package.scan(tools: .nowhere)

        let locations = report.findings.map { $0.locations[0] }
        #expect(locations.map(\.line) == [3, 5, 6])
        #expect(locations.map(\.attachedTo) == [.type, .file, .function])
        #expect(locations.map(\.owner) == ["Lib::Config", nil, "Lib::<top-level code> @ Sources/Lib/main.swift"])
    }

    @Test("@MainActor inside an #if in a declaration's attributes marks the declaration")
    func mainActorInsideIf() {
        let source = """
        #if os(iOS)
        @MainActor
        #endif
        final class Screen {
            #if canImport(UIKit)
            @MainActor
            #else
            @preconcurrency
            #endif
            func refresh() { }
            let handler: @MainActor () -> Void = { }
        }
        """
        let markers = CollectorHarness.markers(source)

        #expect(markers.map(\.rule) == ["mainActorDeclaration", "mainActorDeclaration"])
        #expect(markers.map { $0.places[0].line } == [2, 6])
    }

    @Test("a Task without a closure, or a type named like Task, is not a creation site")
    func notTasks() {
        let source = """
        func wait() async throws {
            try await Task.sleep(for: .seconds(1))
            let task: Task<Void, Never>? = nil
            _ = MyTask { }
            _ = task
        }
        """
        #expect(CollectorHarness.markers(source).isEmpty)
    }

    @Test("async functions, initialisers and getters are marked on their records")
    func asyncRecords() {
        let source = """
        struct Loader {
            init() async { }
            func load() async throws -> Int { 1 }
            func sync() -> Int { 2 }
            var value: Int { get async { 3 } }
        }
        """
        let records = CollectorHarness.collect(source)

        #expect(records.map(\.name) == ["init", "load", "sync", "value"])
        #expect(records.map(\.isAsync) == [true, true, false, true])
    }
}
