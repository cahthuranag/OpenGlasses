import Foundation

/// A part number, said one character at a time (Plan IH §2).
///
/// A number the van has never carried and the manuals do not know is the one place a misheard
/// digit becomes a wrong line of stock, so it is read back slowly enough to catch: "62-23543-01"
/// is "six two, dash, two three five four three, dash, zero one".
enum SpokenPartNumber {

    private static let digits = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
    ]

    static func spoken(_ number: String) -> String {
        var groups: [String] = []
        var current: [String] = []

        func close() {
            if !current.isEmpty { groups.append(current.joined(separator: " ")) }
            current = []
        }

        for character in number.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let digit = digits[String(character)] {
                current.append(digit)
            } else if character.isLetter {
                current.append(String(character).uppercased())
            } else if character == "-" {
                close()
                groups.append("dash")
            } else if character == "/" {
                close()
                groups.append("slash")
            } else if character == "." {
                close()
                groups.append("point")
            } else {
                close()
            }
        }
        close()
        return groups.joined(separator: ", ")
    }
}
