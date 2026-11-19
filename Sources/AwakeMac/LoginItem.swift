import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    static var note: String? {
        switch status {
        case .requiresApproval:
            return L("login.approval")
        default:
            return nil
        }
    }
}
