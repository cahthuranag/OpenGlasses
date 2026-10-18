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
        Formatters.shared.fractional.string(from: date)
    }

    /// Accepts `Z` or a numeric offset (`+13:00`), with or without fractional seconds.
    static func parse(_ raw: String) -> Date? {
        Formatters.shared.fractional.date(from: raw) ?? Formatters.shared.plain.date(from: raw)
    }

    /// One pair of formatters for the process. The stores (Plan IW P1) write every row on every
    /// change, so a formatter per date would cost a formatter per row per write. Configured once and
    /// never mutated afterwards; Foundation's formatters are safe to use from several threads once
    /// configured, which is the guarantee the `@unchecked Sendable` leans on.
    private final class Formatters: @unchecked Sendable {
        static let shared = Formatters()
        let fractional: ISO8601DateFormatter
        let plain: ISO8601DateFormatter

        private init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
        }
    }
}
