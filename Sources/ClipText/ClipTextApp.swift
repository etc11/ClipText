import AppKit
import SwiftUI
import CoreGraphics

@main
enum ClipTextApp {
    static func main() {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--ocr" {
            do {
                let result = try OCR.recognize(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
                print(result.text)
                if let warning = result.warning { fputs("Warning: \(warning)\n", stderr) }
            } catch {
                fputs("\(error)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = CanvasModel()
    private let loginItem = LoginItemController()
    private var captureHotKey: GlobalHotKey?
    private var capturePermission = ScreenCapturePermission()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAtLogin = LaunchContext.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "ClipText")
        button.target = self
        button.action = #selector(toggle)
        button.toolTip = "ClipText — drop an image, or press ⌘⇧2 to capture text"
        let dropView = ImageDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.clicked = { [weak self] in self?.toggle() }
        dropView.receive = { [weak self] pasteboard in
            guard let self else { return false }
            let accepted = self.model.receive(pasteboard)
            self.show()
            return accepted
        }
        button.addSubview(dropView)
        popover.behavior = .transient
        let controller = NSHostingController(rootView:
            CanvasView(model: model, loginItem: loginItem,
                chooseImage: { [weak self] in self?.chooseImage() },
                captureScreen: { [weak self] in self?.captureScreen() },
                openScreenSettings: { [weak self] in self?.openScreenSettings() }))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        installMenu()
        do {
            captureHotKey = try GlobalHotKey { [weak self] in
                Task { @MainActor in self?.captureScreen() }
            }
        } catch {
            model.message = "⌘⇧2 couldn’t be registered. Another app may be using it. Use Capture text instead."
        }
        if !launchedAtLogin { show() }
        model.warmUpOCR()
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ClipText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }

    @objc private func toggle() { if popover.isShown { popover.close() } else { show() } }

    private func show() {
        loginItem.refresh()
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
    }

    private func chooseImage() {
        popover.close()
        let panel = NSOpenPanel()
        panel.title = "Choose an image to read"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url { self.model.load(url: url) }
            self.show()
        }
    }

    private func captureScreen() {
        guard !model.isCapturing else { return }
        model.isCapturing = true
        popover.close()
        guard capturePermission.authorize(preflight: CGPreflightScreenCaptureAccess,
                                           request: CGRequestScreenCaptureAccess) else {
            model.isCapturing = false
            model.needsScreenCapturePermission = true
            model.message = "Enable ClipText in System Settings → Privacy & Security → Screen Recording. If it’s already enabled, quit and reopen ClipText so macOS can apply the permission."
            show()
            return
        }
        model.needsScreenCapturePermission = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ScreenCapture.selectArea() }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.model.isCapturing = false
                switch result {
                case .success(let data):
                    if let data { self.model.load(data: data, name: "Screen selection") }
                case .failure(let error):
                    self.capturePermission.captureFailed()
                    self.model.message = error.localizedDescription
                    self.model.needsScreenCapturePermission = !CGPreflightScreenCaptureAccess()
                }
                self.show()
            }
        }
    }

    private func openScreenSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
