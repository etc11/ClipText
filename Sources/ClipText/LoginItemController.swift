import AppKit
import ServiceManagement
import SwiftUI

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openSettings()
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isUpdating = false
    @Published var errorMessage: String?
    private let service: any LoginItemService

    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    convenience init() { self.init(service: SystemLoginItemService()) }

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    func refresh() { status = service.status }
    func openSettings() { service.openSettings() }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        refresh()
        guard enabled != isRequested else { return }
        isUpdating = true
        errorMessage = nil
        defer {
            refresh()
            isUpdating = false
        }
        do {
            if enabled { try service.register() }
            else { try await service.unregister() }
            refresh()
            if needsApproval { service.openSettings() }
        } catch {
            errorMessage = "Couldn’t \(enabled ? "enable" : "disable") Launch at login. \(error.localizedDescription)"
        }
    }
}

enum LaunchContext {
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
