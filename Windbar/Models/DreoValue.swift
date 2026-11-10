import Foundation

/// A Dreo wire value: JSON scalars come back as bool, int, double, or string
/// depending on the field (e.g. `hoscangle` is a string like "-45,45").
/// The countdown timers (`timeron`/`timeroff`) are the one known exception:
/// they travel as a small object, `{"du": minutes, "ts": epochSeconds}`.
enum DreoValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case object([String: DreoValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: DreoValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "DreoValue is neither bool, int, double, string, nor object"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// For handing to `JSONSerialization`, which needs `Any`, not an enum.
    var jsonObject: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .object(let value): return value.mapValues(\.jsonObject)
        }
    }

    var objectValue: [String: DreoValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var description: String {
        switch self {
        case .bool(let value): return String(value)
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .object(let value):
            // Sorted so two reports of the same state read the same.
            let fields = value.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            return "{" + fields.joined(separator: ", ") + "}"
        }
    }
}
