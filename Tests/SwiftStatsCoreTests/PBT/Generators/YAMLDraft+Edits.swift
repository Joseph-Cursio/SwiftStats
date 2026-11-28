//
//  YAMLDraft+Edits.swift
//  SwiftStatsCoreTests
//
//  Edits of a configuration draft at a path of key texts (`["signals",
//  "hotspot", "threshold"]`): set a value, remove a key, read the mapping
//  at a path, or add a member to it at a position. A key is found by its
//  text, the last member holding it, as the reader names keys; a mapping
//  missing on the way, or a value on the way that isn't a mapping, is
//  made an empty mapping, so any edit applies to any draft.
//

/// Edits of a draft's members at a path of key texts.
extension YAMLDraft {
    /// `members` with the key at `path` given `value`, the member kept in
    /// its place when it is there, else added at the end.
    static func setting(_ value: Self?, at path: [String], in members: [Member]) -> [Member] {
        guard let key = path.first else {
            return members
        }
        let index = members.lastIndex { $0.key.keyText == key }
        let rest = Array(path.dropFirst())
        let newValue = rest.isEmpty ? value : .mapping(setting(value, at: rest, in: nested(index.map { members[$0] })))
        let member = Member(key: index.map { members[$0].key } ?? text(key), value: newValue)
        var edited = members
        if let index {
            edited[index] = member
        } else {
            edited.append(member)
        }
        return edited
    }

    /// `members` without any member whose key is the last of `path`, in
    /// the mapping at the rest of it; unchanged when there is none.
    static func removing(at path: [String], in members: [Member]) -> [Member] {
        guard let key = path.first else {
            return members
        }
        guard path.count > 1 else {
            return members.filter { $0.key.keyText != key }
        }
        guard let index = members.lastIndex(where: { $0.key.keyText == key }),
              case .mapping(let inner)? = members[index].value else {
            return members
        }
        var edited = members
        edited[index] = Member(
            key: members[index].key,
            value: .mapping(removing(at: Array(path.dropFirst()), in: inner))
        )
        return edited
    }

    /// The members of the mapping at `path`; none when there is no mapping
    /// there.
    static func members(at path: [String], in members: [Member]) -> [Member] {
        guard let key = path.first else {
            return members
        }
        let found = members.last { $0.key.keyText == key }
        return Self.members(at: Array(path.dropFirst()), in: nested(found))
    }

    /// `members` with `member` added to the mapping at `path`, at
    /// `position` modulo one more than that mapping's count.
    static func inserting(_ member: Member, at position: Int, under path: [String], in members: [Member]) -> [Member] {
        var inner = Self.members(at: path, in: members)
        inner.insert(member, at: position % (inner.count + 1))
        guard path.isEmpty == false else {
            return inner
        }
        return setting(.mapping(inner), at: path, in: members)
    }

    /// The members of `member`'s value when it is a mapping; none
    /// otherwise.
    private static func nested(_ member: Member?) -> [Member] {
        guard case .mapping(let inner)? = member?.value else {
            return []
        }
        return inner
    }
}
