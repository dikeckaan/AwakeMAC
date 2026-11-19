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
            return "Sistem Ayarları > Genel > Giriş Öğeleri'nden onay gerekiyor."
        default:
            return nil
        }
    }
}
