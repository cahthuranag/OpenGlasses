import Foundation
// Only the logger's value types are stubbed: the full production ring/store/protection code
// is compiled unchanged, except the candidate read-size guard (16 MB rather than 4 MB).
enum PrivacyLog {
    enum Category: String, Codable { case app, camera }
    struct TapToken {}
    static func removeTap(_ token: TapToken) {}
    static func addTap(_ sink: @escaping (PrivacyEvent, String) -> Void) -> TapToken { TapToken() }
}
struct PrivacyToken: Equatable { let raw: String; init(_ raw: String) { self.raw = raw } }
struct PrivacyEvent {
    enum Name: String, Codable { case app, camera }
    enum Key { case event }
    enum Value: Equatable { case token(PrivacyToken) }
    struct Field { let key: Key; let value: Value }
    let category: PrivacyLog.Category
    let name: Name
    let fields: [Field]
}
