// A raw-value enum: RawRepresentable from its raw type; CaseIterable and
// Codable synthesised.
public enum Status: String, CaseIterable, Codable {
    case open
    case closed
}

// Its own allCases makes CaseIterable custom.
public enum Level: Int, CaseIterable {
    case low
    case high

    public static var allCases: [Level] {
        [.high, .low]
    }
}

// Naming RawRepresentable makes it custom.
public struct Code: RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        self.rawValue = rawValue
    }
}

// Encodable and Decodable named apart make Codable, synthesised.
public struct Record: Encodable {
    public let id: Int
}

extension Record: Decodable {}

// CodingKeys makes Codable custom.
public struct Envelope: Codable {
    enum CodingKeys: String, CodingKey {
        case body = "b"
    }

    let body: String
}

// init(from:) in an extension makes Codable custom.
public struct Payload: Codable {
    let size: Int
}

extension Payload {
    public init(from decoder: any Decoder) throws {
        size = 0
    }
}

// Encodable alone is not a kit protocol: no pair.
public struct Summary: Encodable {
    let text: String
}

// A conversion init(from:) and an encode(to:) without an Encoder are no
// Codable witnesses: Codable stays synthesised.
public struct Settings: Codable {
    let name: String

    init(from profile: Profile) {
        name = profile.name
    }

    func encode(to text: inout String) {
        text += name
    }
}
