import Foundation

/// The arithmetic `calculate` evaluates, and the evaluator a rule chain's `calc` and `check` steps
/// run through (Plan JJ P2): numbers, named values, `+ - * /`, parentheses and a unary minus, in
/// doubles.
///
/// A small parser of its own rather than `NSExpression(format:)`, which raises an Objective-C
/// exception Swift cannot catch on a malformed expression ("2 +"), and divides whole numbers as
/// whole numbers ("7 / 2" is 3). A chain's expression is written by hand in a vault file and
/// substituted with values a technician said, so neither is acceptable there. Pure.
enum ArithmeticExpression {

    indirect enum Node: Equatable {
        case number(Double)
        case name(String)
        case negate(Node)
        case binary(Character, Node, Node)
    }

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unexpected(String)
        case unbalanced
        case trailing(String)

        var description: String {
            switch self {
            case .empty: return "the expression is empty"
            case .unexpected(let token): return "'\(token)' is not expected there"
            case .unbalanced: return "a parenthesis is not closed"
            case .trailing(let token): return "'\(token)' follows a complete expression"
            }
        }
    }

    enum EvaluationError: Error, Equatable {
        /// A name with no number behind it.
        case unknownName(String)
        case divisionByZero
        case notFinite
    }

    // MARK: Parsing

    static func parse(_ text: String) throws -> Node {
        var parser = Parser(tokens: try tokens(text))
        guard !parser.tokens.isEmpty else { throw ParseError.empty }
        let node = try parser.expression()
        if let extra = parser.peek { throw ParseError.trailing(extra.text) }
        return node
    }

    /// The names the expression reads, in the order they first appear.
    static func names(in node: Node) -> [String] {
        var out: [String] = []
        func walk(_ node: Node) {
            switch node {
            case .number: break
            case .name(let name): if !out.contains(name) { out.append(name) }
            case .negate(let inner): walk(inner)
            case .binary(_, let left, let right): walk(left); walk(right)
            }
        }
        walk(node)
        return out
    }

    // MARK: Evaluating

    static func evaluate(_ node: Node, value: (String) -> Double?) -> Result<Double, EvaluationError> {
        func run(_ node: Node) throws -> Double {
            switch node {
            case .number(let number): return number
            case .name(let name):
                guard let number = value(name) else { throw EvaluationError.unknownName(name) }
                return number
            case .negate(let inner): return -(try run(inner))
            case .binary(let op, let left, let right):
                let l = try run(left), r = try run(right)
                switch op {
                case "+": return l + r
                case "-": return l - r
                case "*": return l * r
                default:
                    guard r != 0 else { throw EvaluationError.divisionByZero }
                    return l / r
                }
            }
        }
        do {
            let result = try run(node)
            return result.isFinite ? .success(result) : .failure(.notFinite)
        } catch let error as EvaluationError {
            return .failure(error)
        } catch {
            return .failure(.notFinite)
        }
    }

    /// An expression of numbers only, as `calculate` takes it; nil when it does not parse or does
    /// not evaluate.
    static func evaluate(_ text: String) -> Double? {
        guard let node = try? parse(text), names(in: node).isEmpty,
              case .success(let value) = evaluate(node, value: { _ in nil }) else { return nil }
        return value
    }

    // MARK: Tokens

    struct Token: Equatable {
        enum Kind: Equatable { case number(Double), name(String), symbol(Character) }
        let kind: Kind
        let text: String
    }

    static func tokens(_ text: String) throws -> [Token] {
        var out: [Token] = []
        let characters = Array(text.replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{00D7}", with: "*").replacingOccurrences(of: "\u{00F7}", with: "/"))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character.isNumber || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                var end = index
                var seenPoint = false
                while end < characters.count, characters[end].isNumber || (characters[end] == "." && !seenPoint) {
                    if characters[end] == "." { seenPoint = true }
                    end += 1
                }
                let literal = String(characters[index..<end])
                guard let number = Double(literal) else { throw ParseError.unexpected(literal) }
                out.append(Token(kind: .number(number), text: literal))
                index = end
                continue
            }
            if character.isLetter || character == "_" {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                    end += 1
                }
                let name = String(characters[index..<end])
                out.append(Token(kind: .name(name), text: name))
                index = end
                continue
            }
            guard "+-*/()".contains(character) else { throw ParseError.unexpected(String(character)) }
            out.append(Token(kind: .symbol(character), text: String(character)))
            index += 1
        }
        return out
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var peek: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func take(_ symbol: Character) -> Bool {
            guard let token = peek, token.kind == .symbol(symbol) else { return false }
            position += 1
            return true
        }

        mutating func expression() throws -> Node {
            var node = try term()
            while let token = peek, case .symbol(let op) = token.kind, op == "+" || op == "-" {
                position += 1
                node = .binary(op, node, try term())
            }
            return node
        }

        mutating func term() throws -> Node {
            var node = try factor()
            while let token = peek, case .symbol(let op) = token.kind, op == "*" || op == "/" {
                position += 1
                node = .binary(op, node, try factor())
            }
            return node
        }

        mutating func factor() throws -> Node {
            guard let token = peek else { throw ParseError.unexpected("the end") }
            switch token.kind {
            case .number(let value):
                position += 1
                return .number(value)
            case .name(let name):
                position += 1
                return .name(name)
            case .symbol("-"):
                position += 1
                return .negate(try factor())
            case .symbol("+"):
                position += 1
                return try factor()
            case .symbol("("):
                position += 1
                let inner = try expression()
                guard take(")") else { throw ParseError.unbalanced }
                return inner
            case .symbol:
                throw ParseError.unexpected(token.text)
            }
        }
    }
}
