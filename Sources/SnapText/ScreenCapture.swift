import Foundation

enum ScreenCapture {
    struct ProcessResult {
        let status: Int32
        let error: String
    }

    enum CaptureError: LocalizedError {
        case failed
        var errorDescription: String? {
            "The screen selection couldn’t be captured. Check Screen Recording permission and try again."
        }
    }

    // The injectable executor lets tests verify cancellation and deletion of
    // temporary screen content without invoking the interactive selector.
    static func selectArea(execute: (URL) throws -> ProcessResult = runSelector) throws -> Data? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapText-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("selection.png")
        let result = try execute(output)
        if result.status == 0, FileManager.default.fileExists(atPath: output.path) {
            return try Data(contentsOf: output)
        }
        // Escape creates no file. Preserve the existing OCR result on cancel.
        if !FileManager.default.fileExists(atPath: output.path),
           (result.status == 0 || result.status == 1),
           (result.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            result.error.localizedCaseInsensitiveContains("cancel")) {
            return nil
        }
        throw CaptureError.failed
    }

    private static func runSelector(output: URL) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", output.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, error: String(decoding: errorData, as: UTF8.self))
    }
}
