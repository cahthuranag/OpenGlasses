import Foundation

@MainActor
final class ManualCaptureTool: NativeTool {
    let name = "manual_capture"
    let description = "Photograph a paper manual with the phone's document camera. 'start' opens a request on the phone; the technician must photograph and save the pages. 'status' or 'list' reads local captures and recognition progress; 'discard' with the exact capture id forgets it. These are unreviewed photographed manuals, not pool-approved documents. Recognition reads text only; verify numbers and diagrams against the photographed page. Never photograph customer paperwork or service logs."
    let parametersSchema: [String:Any] = ["type":"object","properties":[
        "action":["type":"string","enum":["start","status","list","discard"]],
        "title":["type":"string"],"id":["type":"string"]],"required":["action"]]
    func execute(args:[String:Any]) async throws -> String {
        if !Config.fieldAssistActive {
            let action = args["action"] as? String ?? "status"
            if action == "start" { return await PersonalManualCapture.shared.start(title: args["title"] as? String ?? "Photographed manual") }
            if action == "discard", let id = args["id"] as? String,
               let manual = PersonalManualLibrary.shared.manuals.first(where: { $0.id == id && $0.document.personalCapture == true }) {
                await PersonalManualLibrary.shared.remove(manual)
                return PersonalManualLibrary.shared.status
            }
            guard PersonalManualLibrary.canManage else { return MyManualsPaywallCopy.locked }
            return PersonalManualLibrary.shared.manuals.filter { $0.document.personalCapture == true }
                .map { "\($0.id): \($0.document.title)" }.joined(separator: "; ")
                + " " + PersonalManualCapture.shared.status
        }
        let service = ManualCaptureService.shared
        let action = args["action"] as? String ?? "status"
        if action == "discard" {
            guard let id = args["id"] as? String else { return "Name the exact photographed-manual id to forget." }
            do { try service.discard(id);return service.status }
            catch { return "The manual could not be fully removed. Unlock the phone and try again." }
        }
        guard CapturedManualCatalog.mayUse else { return "Photographed manuals are unavailable under the current Field Assist, privacy or organisation policy." }
        switch action {
        case "start":return service.start(title:args["title"] as? String)
        case "status","list":return service.list().isEmpty ? "No photographed manuals are saved." : service.list()
        default:return "Use start, status, list or discard."
        }
    }
}
