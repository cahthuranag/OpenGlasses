import Foundation

/// Evaluates mathematical expressions with input sanitization, through `ArithmeticExpression`.
struct CalculatorTool: NativeTool {
    let name = "calculate"
    let description = "Evaluate a mathematical expression. Supports +, -, *, /, parentheses, and decimal numbers."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "expression": [
                "type": "string",
                "description": "The math expression to evaluate, e.g. '(45 * 2) + 100 / 4'"
            ]
        ],
        "required": ["expression"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let expression = args["expression"] as? String, !expression.isEmpty else {
            return "No expression provided."
        }

        // Sanitize: only allow digits, operators, parens, decimal points, spaces
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        let sanitized = expression.unicodeScalars.filter { allowed.contains($0) }
        let cleanExpr = String(String.UnicodeScalarView(sanitized))

        guard !cleanExpr.isEmpty else {
            return "Invalid expression. Only numbers and basic operators (+, -, *, /) are supported."
        }

        // The shared evaluator (`ArithmeticExpression`), which a rule chain's `calc` steps use too:
        // a malformed expression is a refusal rather than an uncatchable NSExpression exception,
        // and 7 / 2 is 3.5.
        guard let doubleResult = ArithmeticExpression.evaluate(cleanExpr) else {
            return "Couldn't evaluate that expression."
        }

        // Format nicely: show as integer if it's a whole number
        if doubleResult == doubleResult.rounded() && abs(doubleResult) < 1e15 {
            return "\(expression) = \(Int(doubleResult))"
        }
        return "\(expression) = \(doubleResult)"
    }
}
