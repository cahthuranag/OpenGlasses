import Foundation

/// Converts between currencies using the free Frankfurter API, falling back to the free keyless
/// AllRatesToday ECB table (https://allratestoday.com/api/open/latest/{BASE}) when Frankfurter is
/// unreachable, answers non-200 or returns a body without the requested rate. Both are public ECB
/// mirrors that need no API key, so the wearer sees the same answer whichever one replied.
struct CurrencyTool: NativeTool {
    /// Session the rate requests go through. Tests inject a stubbed one.
    var session: URLSession? = nil

    let name = "convert_currency"
    let description = "Convert an amount between currencies using live exchange rates. No API key needed."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "amount": [
                "type": "number",
                "description": "The amount to convert"
            ],
            "from": [
                "type": "string",
                "description": "Source currency code, e.g. 'USD', 'EUR', 'GBP'"
            ],
            "to": [
                "type": "string",
                "description": "Target currency code, e.g. 'EUR', 'JPY', 'GBP'"
            ]
        ],
        "required": ["amount", "from", "to"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard MedicalEgressGuard.allows(.currencyRates) else { return MedicalEgressRefusal.userMessage }
        let amount: Double
        if let a = args["amount"] as? Double {
            amount = a
        } else if let a = args["amount"] as? Int {
            amount = Double(a)
        } else {
            return "Missing or invalid amount."
        }

        guard let from = (args["from"] as? String)?.uppercased(), !from.isEmpty else {
            return "Missing source currency code."
        }
        guard let to = (args["to"] as? String)?.uppercased(), !to.isEmpty else {
            return "Missing target currency code."
        }

        if from == to {
            return "\(formatAmount(amount)) \(from) = \(formatAmount(amount)) \(to) (same currency)"
        }

        guard let rate = await fetchRate(from: from, to: to) else {
            return "Currency conversion service is temporarily unavailable. Check that \(from) and \(to) are valid currency codes."
        }

        let converted = amount * rate
        return "\(formatAmount(amount)) \(from) = \(formatAmount(converted)) \(to) (rate: \(String(format: "%.4f", rate)))"
    }

    /// Frankfurter first, AllRatesToday second. Each source is a 200 whose JSON `rates[to]` is a
    /// number; anything else (network error, other status, unparsable body, missing code) moves on
    /// to the next. `nil` when neither answered.
    func fetchRate(from: String, to: String) async -> Double? {
        let sources = [
            "https://api.frankfurter.dev/v1/latest?base=\(from)&symbols=\(to)",
            "https://allratestoday.com/api/open/latest/\(from)"
        ]
        for urlString in sources {
            guard let url = URL(string: urlString) else { continue }
            if let rate = await fetchRate(url: url, code: to) { return rate }
        }
        return nil
    }

    private func fetchRate(url: URL, code: String) async -> Double? {
        let session = self.session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            return URLSession(configuration: config)
        }()

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Any] else {
            return nil
        }
        if let rate = rates[code] as? Double { return rate }
        if let rate = rates[code] as? Int { return Double(rate) }
        return nil
    }

    private func formatAmount(_ value: Double) -> String {
        if value == value.rounded() && value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
