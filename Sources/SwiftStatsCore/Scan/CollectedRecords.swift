//
//  CollectedRecords.swift
//  SwiftStatsCore
//
//  What one walk over the parsed files yields, before keys are resolved and
//  scores attached.
//

/// The function, type and file records of a scan, in walk order.
struct CollectedRecords {
    /// Function records.
    var records: [FunctionRecord] = []
    /// Type records.
    var types: [TypeRecord] = []
    /// File records.
    var files: [FileRecord] = []
    /// Declarations the API surface counts.
    var declarations: [APIDeclaration] = []
    /// SwiftStats' own risk markers.
    var markers: [RawFinding] = []
    /// Each file's top-level statement lines, by path.
    var topLevelLines: [String: Set<Int>] = [:]
    /// Each file's `private` and `fileprivate` types, as dotted paths, by path.
    var fileScopedTypes: [String: Set<String>] = [:]
    /// Each file's member records' selectors (`MemberSelector`), by the
    /// record's start, by path.
    var selectors: [String: [SourcePosition: String]] = [:]
    /// Each file's function and initialiser records' parameters
    /// (`CallSignature`), by the record's start, by path.
    var signatures: [String: [SourcePosition: CallSignature]] = [:]
    /// Each file's law-detection facts.
    var laws: [LawFileFacts] = []
    /// The test-target files whose leading comments carry a
    /// SwiftInferProperties suggestion identity, by identity.
    var stubs: [String: Set<String>] = [:]
    /// The law each `@CheckProperty` the macro accepts checks, by the
    /// place its marker names.
    var checkProperties: [RawFinding.Place: CheckPropertyKind] = [:]
}
