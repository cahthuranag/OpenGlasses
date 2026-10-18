import Foundation

/// The one JSON shape goals and activity entries are written in (Plan IW).
///
/// Dates are ISO 8601 strings with fractional seconds, keys are sorted, and decoding accepts a date
/// with or without the fraction. Fixed here rather than at each store, so a file written by one
/// build reads in the next whatever encoder defaults Foundation ships with — the fixture tests pin
/// this format, not Foundation's.
enum RecordJSONCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "unreadable date")
            }
            return date
        }
        return decoder
    }

    static func format(_ date: Date) -> String {
        formatter(fractional: true).string(from: date)
    }

    /// Accepts `Z` or a numeric offset (`+13:00`), with or without fractional seconds.
    static func parse(_ raw: String) -> Date? {
        formatter(fractional: true).date(from: raw) ?? formatter(fractional: false).date(from: raw)
    }

    /// A fresh formatter per call: `ISO8601DateFormatter` is not `Sendable`, and these run rarely.
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds]
                                             : [.withInternetDateTime]
        return formatter
    }
}
