import AppKit
import SwiftUI

// Neutral surfaces, small radii, and explicit borders keep the utility compact.
private struct SnapColors {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    var background: Color { Color(hex: dark ? 0x0d1117 : 0xffffff) }
    var surface: Color { Color(hex: dark ? 0x161b22 : 0xf6f8fa) }
    var hover: Color { Color(hex: dark ? 0x21262d : 0xeaeef2) }
    var border: Color { Color(hex: dark ? 0x30363d : 0xd0d7de) }
    var text: Color { Color(hex: dark ? 0xe6edf3 : 0x1f2328) }
    var muted: Color { Color(hex: dark ? 0x8b949e : 0x656d76) }
    var link: Color { Color(hex: dark ? 0x58a6ff : 0x0969da) }
    var green: Color { Color(hex: dark ? 0x238636 : 0x1f883d) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

struct CanvasView: View {
    @ObservedObject var model: CanvasModel
    @ObservedObject var loginItem: LoginItemController
    let chooseImage: () -> Void
    let captureScreen: () -> Void
    let openScreenSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: SnapColors { SnapColors(scheme: colorScheme) }
    private var hasContent: Bool {
        model.image != nil || !model.text.isEmpty || model.message != nil || model.isProcessing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(spacing: 6) {
                sourceCard
                inputActions
                captureAction
            }
            if model.isProcessing {
                processingCard
            } else if !model.text.isEmpty {
                resultCard
            }
            if let message = model.message { notice(message) }
            footer
        }
        .padding(12)
        .frame(width: 360)
        .foregroundStyle(colors.text)
        .background(colors.background)
        .tint(colors.link)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .alert("Launch at login", isPresented: Binding(
            get: { loginItem.errorMessage != nil },
            set: { if !$0 { loginItem.errorMessage = nil } })) {
                Button("OK", role: .cancel) { loginItem.errorMessage = nil }
                Button("Open Login Items", action: loginItem.openSettings)
            } message: {
                Text(loginItem.errorMessage ?? "")
            }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
            Text("ClipText").font(.system(size: 13, weight: .semibold))
            Spacer()
            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isRequested },
                    set: { enabled in Task { await loginItem.setEnabled(enabled) } }))
                    .disabled(loginItem.isUpdating)
                if loginItem.needsApproval {
                    Text("Waiting for macOS approval")
                    Button("Approve in Login Items…", action: loginItem.openSettings)
                }
                Divider()
                Button("Quit ClipText") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("ClipText options")
        }.frame(height: 24)
    }

    private var sourceCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(colors.surface)
            RoundedRectangle(cornerRadius: 6).strokeBorder(colors.border,
                style: StrokeStyle(lineWidth: 1, dash: model.image == nil ? [3, 3] : []))
            HStack(spacing: 10) {
                if let image = model.image {
                    Image(nsImage: image).resizable().scaledToFit().padding(3)
                        .frame(width: 36, height: 36)
                        .background(colors.background, in: RoundedRectangle(cornerRadius: 3))
                        .accessibilityLabel("Source image")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.filename).font(.system(size: 11, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        Text("Drop another image to replace").font(.system(size: 10)).foregroundStyle(colors.muted)
                    }
                } else {
                    Image(systemName: "photo").font(.system(size: 19, weight: .regular))
                        .foregroundStyle(colors.muted).frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Drop an image").font(.system(size: 12, weight: .medium))
                        Text("Or capture a screen area below").font(.system(size: 10)).foregroundStyle(colors.muted)
                    }
                }
                Spacer(minLength: 0)
            }.padding(10)
            DropSurface { model.receive($0) }
        }.frame(height: model.image == nil ? 64 : 56)
    }

    private var inputActions: some View {
        HStack(spacing: 6) {
            Button(action: chooseImage) {
                Label("Choose image", systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity)
            }
            Button { model.receive(.general) } label: {
                Label("Paste image", systemImage: "clipboard").lineLimit(1).frame(maxWidth: .infinity)
            }
            Button(action: model.clear) { Label("Clear", systemImage: "xmark") }
                .disabled(!hasContent)
                .help("Clear the current image and extracted text.")
        }
        .buttonStyle(SnapControlStyle())
        .disabled(model.isCapturing)
    }

    private var captureAction: some View {
        Button(action: captureScreen) {
            HStack(spacing: 7) {
                Image(systemName: "viewfinder").font(.system(size: 12, weight: .medium))
                Text("Capture text").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("⌘⇧2").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(SnapCaptureStyle())
        .disabled(model.isCapturing)
        .help("Select an area of the screen to extract its text. Press Escape to cancel.")
    }

    private var processingCard: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Reading English / 中文…").font(.system(size: 11)).foregroundStyle(colors.muted)
            Spacer()
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 44)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(colors.border))
    }

    private var resultCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Extracted text").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: model.copyText) {
                    Label(model.copied ? "Copied" : "Copy text",
                          systemImage: model.copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(SnapControlStyle(accented: true))
            }
            .padding(.horizontal, 8).padding(.vertical, 5).background(colors.surface)
            rule
            TextEditor(text: $model.text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4).padding(.vertical, 6)
                .frame(height: 132)
                .accessibilityLabel("Extracted text, editable")
                .onChange(of: model.text) { model.copied = false }
            rule
            HStack {
                Text("\(model.text.count.formatted()) characters")
                    .font(.system(size: 10)).foregroundStyle(colors.muted)
                Spacer()
                readAgainAction
            }
            .padding(.horizontal, 8).frame(height: 28).background(colors.surface)
        }
        .background(colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.border))
    }

    @ViewBuilder private var readAgainAction: some View {
        if model.canReadAccurately && model.resultMode != .accurate {
            Button(action: model.readAccurately) { Label("Read Again", systemImage: "arrow.clockwise") }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.link)
                .help("Slower recognition for difficult text and additional languages. Replaces the current result.")
        }
    }

    private func notice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                Text(message).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11)).foregroundStyle(colors.muted)
            if model.canRetry {
                Button("Try again", action: model.retry).buttonStyle(SnapControlStyle())
            }
            if model.needsScreenCapturePermission {
                Button("Open Screen Recording Settings", action: openScreenSettings).buttonStyle(SnapControlStyle())
            }
            if model.text.isEmpty { readAgainAction }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(colors.border))
    }

    private var rule: some View { colors.border.frame(height: 1) }

    private var footer: some View {
        VStack(spacing: 8) {
            rule
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                Text("On-device · No uploads")
                Spacer()
                if let summary = model.recognitionSummary { Text(summary).monospacedDigit() }
            }.font(.system(size: 10)).foregroundStyle(colors.muted)
        }
    }
}

private struct SnapControlStyle: ButtonStyle {
    var accented = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let colors = SnapColors(scheme: colorScheme)
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accented ? colors.link : colors.text)
            .padding(.horizontal, 8).frame(height: 26)
            .background(hovering || configuration.isPressed ? colors.hover : colors.surface,
                in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(colors.border))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hovering = $0 }
    }
}

private struct SnapCaptureStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let colors = SnapColors(scheme: colorScheme)
        configuration.label.foregroundStyle(.white)
            .background(colors.green.opacity(configuration.isPressed ? 0.8 : hovering ? 0.9 : 1),
                in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.15)))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}
