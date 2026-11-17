//
//  SitrepCounter.swift
//  SwiftStatsCore
//
//  Aggregates per-file facts into Sitrep's report, following Sitrep's
//  `Scan.collate` and `Results` rules, quirks included (PRD §7.1). Where
//  Sitrep's result depends on dictionary or file-system order, ties are
//  broken deterministically instead: longest file by path order, longest
//  type and import order by name, and a type name declared with different
//  first parents by its first declaration in path order.
//

/// Builds Sitrep-compatible counts.
enum SitrepCounter {
    /// UIKit base classes whose subclasses count as UIKit code (Sitrep's
    /// `Type.uiKitClasses`).
    static let uiKitClasses = [
        "MKAnnotationView", "MKMapView", "UIApplication", "UIBarButtonItem", "UIBarItem", "UIButton",
        "UICollectionView", "UICollectionViewCell", "UIControl", "UIImageView", "UILabel",
        "UINavigationController", "UIPickerView", "UIScrollView", "UISplitViewController", "UIStackView",
        "UISwitch", "UITabBarController", "UITabBarItem", "UITableView", "UITableViewCell",
        "UITableViewController", "UITextField", "UITextView", "UIView", "UIViewController", "UIWindow"
    ]

    /// SwiftUI protocols whose conformers count as SwiftUI code (Sitrep's
    /// `Type.swiftUIProtocols`).
    static let swiftUIProtocols = ["App", "ButtonStyle", "ShapeStyle", "View", "ViewModifier", "Label"]

    /// Representable protocols that bridge UIKit into SwiftUI.
    private static let representables = ["UIViewRepresentable", "UIViewControllerRepresentable"]

    /// The report for `files`, which must be in scan order.
    static func report(for files: [SitrepFileFacts]) -> SitrepReport {
        let types = files.flatMap(\.types)
        let classes = types.filter { $0.kind == "class" }
        let structs = types.filter { $0.kind == "struct" }
        let extensions = types.filter { $0.kind == "extension" }

        return SitrepReport(
            scanStats: SitrepScanStats(
                scannedFiles: files.count,
                totalLinesOfCode: files.reduce(0) { $0 + $1.newlineCount } + 1,
                totalStrippedLinesOfCode: files.reduce(0) { $0 + max($1.nonEmptyLineCount - 1, 0) } + 1,
                longestFile: longestFile(in: files),
                longestType: longestType(in: types),
                uiKitLinesOfCode: uiKitLines(classes: classes, structs: structs, extensions: extensions),
                swiftUILinesOfCode: swiftUILines(structs: structs, extensions: extensions)
            ),
            objects: SitrepObjects(
                structs: structs.count,
                classes: classes.count,
                enums: types.filter { $0.kind == "enum" }.count,
                protocols: types.filter { $0.kind == "protocol" }.count,
                extensions: extensions.count
            ),
            imports: importCounts(in: files),
            inheritances: [
                SitrepStat(
                    name: "UIViewController",
                    value: classes.filter { $0.inheritance.first == "UIViewController" }.count
                ),
                SitrepStat(name: "UIView", value: classes.filter { $0.inheritance.first == "UIView" }.count),
                SitrepStat(name: "SwiftUI.View", value: structs.filter { $0.inheritance.contains("View") }.count)
            ]
        )
    }

    /// The first file with the most non-empty lines.
    private static func longestFile(in files: [SitrepFileFacts]) -> SitrepStat? {
        var best: SitrepStat?
        for file in files {
            let length = max(file.nonEmptyLineCount, 1)
            if length > (best?.value ?? 0) {
                let name = file.path.split(separator: "/").last.map(String.init) ?? file.path
                best = SitrepStat(name: name, value: length)
            }
        }
        return best
    }

    /// The type name with the most non-empty lines over all its declarations
    /// and extensions; ties go to the alphabetically first name.
    private static func longestType(in types: [SitrepTypeFact]) -> SitrepStat? {
        var lengths: [String: Int] = [:]
        for type in types {
            lengths[type.name, default: 0] += type.lineCount
        }
        return lengths
            .min { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key }
            .map { SitrepStat(name: $0.key, value: $0.value) }
    }

    /// Import counts per module path, most imported first, then by name.
    private static func importCounts(in files: [SitrepFileFacts]) -> [SitrepStat] {
        var counts: [String: Int] = [:]
        for name in files.flatMap(\.imports) {
            counts[name, default: 0] += 1
        }
        return counts
            .map { SitrepStat(name: $0.key, value: $0.value) }
            .sorted { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.name < rhs.name }
    }

    /// Sitrep's `uiKitLinesOfCode`.
    private static func uiKitLines(
        classes: [SitrepTypeFact],
        structs: [SitrepTypeFact],
        extensions: [SitrepTypeFact]
    ) -> Int {
        let uiKitTypes = extending(classes, from: uiKitClasses)
        let ports = structs.filter { type in
            type.inheritance.first.map(representables.contains) ?? false
        }
        let extensionTypes = uiKitTypes.map(\.name) + uiKitClasses + ports.map(\.name) + representables
        return lineTotal(uiKitTypes) + lineTotal(ports)
            + lineTotal(extensions.filter { extensionTypes.contains($0.name) })
    }

    /// Sitrep's `swiftUILinesOfCode`.
    private static func swiftUILines(structs: [SitrepTypeFact], extensions: [SitrepTypeFact]) -> Int {
        let uiTypes = extending(structs, from: swiftUIProtocols)
        let extensionTypes = uiTypes.map(\.name) + swiftUIProtocols
        return lineTotal(uiTypes) + lineTotal(extensions.filter { extensionTypes.contains($0.name) })
    }

    /// Class and struct names declared more than once with different first
    /// parents, where the choice changes the UIKit or SwiftUI line counts:
    /// one parent leads to a UIKit class (or SwiftUI protocol) and another
    /// doesn't. Sitrep keeps whichever declaration it reads last, in
    /// file-system order, so for these names its counts can't be reproduced.
    static func namesWithConflictingParents(in files: [SitrepFileFacts]) -> [String] {
        let types = files.flatMap(\.types)
        var conflicting = Set<String>()
        for (kind, bases) in [("class", uiKitClasses), ("struct", swiftUIProtocols)] {
            let inheriting = types.filter { $0.kind == kind && $0.inheritance.isEmpty == false }
            let firstParent = firstParents(of: inheriting)
            let options = Dictionary(grouping: inheriting, by: \.name)
                .mapValues { Set($0.compactMap(\.inheritance.first)) }
            for (name, parents) in options where parents.count > 1 {
                let outcomes = Set(parents.map { reaches($0, bases: Set(bases), firstParent: firstParent) })
                if outcomes.count > 1 {
                    conflicting.insert(name)
                }
            }
        }
        return conflicting.sorted()
    }

    /// Each name's first parent, the first declaration in path order winning.
    private static func firstParents(of types: [SitrepTypeFact]) -> [String: String] {
        var firstParent: [String: String] = [:]
        for type in types {
            if let parent = type.inheritance.first, firstParent[type.name] == nil {
                firstParent[type.name] = parent
            }
        }
        return firstParent
    }

    /// Whether the chain of first parents starting at `name` reaches a base.
    private static func reaches(_ name: String, bases: Set<String>, firstParent: [String: String]) -> Bool {
        var current: String? = name
        var visited = Set<String>()
        while let next = current, visited.insert(next).inserted {
            if bases.contains(next) {
                return true
            }
            current = firstParent[next]
        }
        return false
    }

    /// Sitrep's `extending(from:)`: for each base name in order, the types
    /// whose chain of first inherited types reaches it. A type can appear
    /// once per base it reaches, as in Sitrep. When a name is declared with
    /// different first parents, the first declaration in path order wins.
    private static func extending(_ types: [SitrepTypeFact], from bases: [String]) -> [SitrepTypeFact] {
        let firstParent = firstParents(of: types)
        return bases.flatMap { base in
            types.filter { type in
                var current: String? = type.name
                var visited = Set<String>()
                while let name = current, visited.insert(name).inserted {
                    if name == base {
                        return true
                    }
                    current = firstParent[name]
                }
                return false
            }
        }
    }

    /// Total non-empty lines of `types`.
    private static func lineTotal(_ types: [SitrepTypeFact]) -> Int {
        types.reduce(0) { $0 + $1.lineCount }
    }
}
