@testable import SwiftStatsCore
import Testing

/// Each record's owning type (M5): the enclosing types' names as the type
/// records name them, the file when one of them is file-scoped, and a type
/// attachment's owner text with that file, so two files' same-named private
/// types never merge.
@Suite("Type paths")
struct TypePathTests {
    @Test("""
        a record's type path joins its enclosing types' names, an extension's without its where clause; \
        nested functions, initialiser contexts and top-level code have none, a subscript's accessors its own
        """)
    func typePaths() {
        let source = """
            func free() {}
            struct Outer<Element> {
                struct Inner {
                    func work() {
                        func helper() {}
                    }
                }
                subscript(index: Int) -> Int {
                    get { index }
                    set {}
                }
                var closure: () -> Void = {
                    func local() {}
                }
            }
            extension Outer.Inner where Element: Equatable {
                func same() -> Bool { true }
            }
            private extension Outer {
                func hidden() {}
            }
            print(1)
            """

        let records = CollectorHarness.collect(source)
        let paths = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.typePath) })

        #expect(paths == [
            "Lib::func free()": nil,
            "Lib::Outer.Inner::func work()": "Outer.Inner",
            "Lib::Outer.Inner::func work() / func helper()": nil,
            "Lib::Outer::subscript(_: Int) -> Int": "Outer",
            "Lib::Outer::subscript(_: Int) -> Int / { get }": "Outer",
            "Lib::Outer::subscript(_: Int) -> Int / { set }": "Outer",
            "Lib::Outer::var closure: () -> Void = <initializer> / func local()": nil,
            "Lib::Outer.Inner where Element: Equatable::func same() -> Bool": "Outer.Inner",
            "Lib::Outer::func hidden() @ Sources/Lib/File.swift": "Outer",
            "Lib::<top-level code> @ Sources/Lib/File.swift": nil
        ])
        #expect(records.allSatisfy { $0.typeFile == nil })
    }

    @Test("a record in a private or fileprivate type, or a type nested in one or extending one, has its file")
    func typeFiles() {
        let source = """
            private struct Secret {
                struct Inner {
                    func deep() {}
                }
                func run() {}
            }
            extension Secret {
                func more() {}
            }
            extension Visible {
                fileprivate struct Hidden {
                    func work() {}
                }
                func open() {}
            }
            """

        let records = CollectorHarness.collect(source, file: "Sources/Lib/A.swift")
        let files = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0.typeFile) })

        #expect(files == [
            "deep": "Sources/Lib/A.swift",
            "run": "Sources/Lib/A.swift",
            "more": "Sources/Lib/A.swift",
            "work": "Sources/Lib/A.swift",
            "open": nil
        ])
    }

    @Test("a finding on a file-scoped type names the type with its file, so two files' Secret types stay apart")
    func fileScopedOwners() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/A.swift": "fileprivate struct Secret {\n    var name: String!\n}\n",
            "Sources/Lib/B.swift": "private struct Secret {\n    var name: String!\n}\n",
            "Sources/Lib/C.swift": "struct Open {\n    var name: String!\n}\n"
        ])
        defer { package.remove() }

        let report = try package.scan(tools: .nowhere)

        let owners = report.findings
            .filter { $0.rule == "implicitlyUnwrappedOptional" }
            .compactMap(\.locations.first?.owner)
        #expect(owners == ["Lib::Secret @ Sources/Lib/A.swift", "Lib::Secret @ Sources/Lib/B.swift", "Lib::Open"])
    }
}
