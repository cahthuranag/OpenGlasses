import Foundation

/// Pure scope rule. Directory identity, serial and a near vault match cannot widen access.
struct CapturedManualAccess: Equatable, Sendable {
    let scope: CapturedManualContract.Scope
    let sessionID: String
    let unitID: String
    let confirmedModelToken: String
    var confirmedAliases: Set<String> = []
    var enabled = true

    func permits(_ m: CapturedManualContract.Manifest) -> Bool {
        guard enabled, m.scope == scope else { return false }
        guard !m.confirmedModelToken.isEmpty else {
            return m.sessionID == sessionID && m.unitID == unitID
        }
        return !confirmedModelToken.isEmpty && (m.confirmedModelToken == confirmedModelToken
            || confirmedAliases.contains(m.confirmedModelToken))
    }
}

