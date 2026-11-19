import AppKit
import SwiftUI

@MainActor
final class CanvasModel: ObservableObject {
    @Published var text = ""
    @Published var image: NSImage?
    @Published var filename = ""
    @Published var isProcessing = false
    @Published var message: String?
    @Published var copied = false
    @Published var canRetry = false
    @Published var recognitionSummary: String?
    @Published var resultMode: OCRMode?
    @Published var isCapturing = false
    @Published var needsScreenCapturePermission = false
    var canReadAccurately: Bool { currentData != nil && !isProcessing }
    private var currentData: Data?
    private let ocrWorker: OCRWorker
    private var generation = UUID()

    init(ocrWorker: OCRWorker = .shared) { self.ocrWorker = ocrWorker }

    func warmUpOCR() { ocrWorker.warmUp() }

    func load(data: Data, name: String, mode: OCRMode = .automatic) {
        let started = ProcessInfo.processInfo.systemUptime
        let token = UUID()
        generation = token
        text = ""
        copied = false
        filename = name
        image = NSImage(data: data)
        message = nil
        isProcessing = true
        currentData = data
        canRetry = false
        recognitionSummary = nil
        resultMode = nil
        ocrWorker.recognize(data: data, mode: mode) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.isProcessing = false
                switch result {
                case .success(let result):
                    self.text = result.text
                    self.message = result.warning
                    self.resultMode = result.mode
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    let modeName = result.mode == .automatic ? "Auto" : result.mode == .fast ? "Fast" : "Accurate"
                    self.recognitionSummary = String(format: "%@ · %.2f s", modeName, elapsed)
                    if result.text.isEmpty {
                        self.message = "No text found. Try Read Again, or use a clearer crop."
                    }
                case .failure(let error):
                    self.message = error.localizedDescription
                    self.canRetry = true
                }
            }
        }
    }

    func load(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 100_000_000 else {
                message = "This file is too large. Choose an image under 100 MB."
                return
            }
            load(data: try Data(contentsOf: url), name: url.lastPathComponent)
        } catch { message = "Couldn’t open this image: \(error.localizedDescription)" }
    }

    @discardableResult
    func receive(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count == 1 else { message = "Drop one image at a time."; return false }
            load(url: urls[0])
            return true
        }
        if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            load(data: data, name: "Clipboard image")
            return true
        }
        message = "Copy or drop an image to extract its text."
        return false
    }

    func copyText() {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    func retry() {
        guard let currentData, !isProcessing else { return }
        load(data: currentData, name: filename, mode: .automatic)
    }

    func readAccurately() {
        guard let currentData, !isProcessing else { return }
        load(data: currentData, name: filename, mode: .accurate)
    }

    func clear() {
        generation = UUID()
        text = ""
        image = nil
        filename = ""
        message = nil
        isProcessing = false
        copied = false
        currentData = nil
        canRetry = false
        recognitionSummary = nil
        resultMode = nil
    }
}
