import Foundation

/// One queue owns warm-up and user requests, so they never initialize competing
/// copies of Vision's model. All state below is protected by stateLock.
final class OCRWorker: @unchecked Sendable {
    static let shared = OCRWorker()
    private let queue: DispatchQueue
    private let recognizeImage: (Data, OCRMode) throws -> OCRResult
    private let initializeEngine: () throws -> Void
    private let stateLock = NSLock()
    private var warmupScheduled = false
    private var scanRequested = false

    init(queue: DispatchQueue = DispatchQueue(label: "local.snaptext.ocr", qos: .utility),
         recognize: @escaping (Data, OCRMode) throws -> OCRResult = { try OCR.recognize(data: $0, mode: $1) },
         warmup: @escaping () throws -> Void = OCRWarmup.perform) {
        self.queue = queue
        recognizeImage = recognize
        initializeEngine = warmup
    }

    func warmUp() {
        stateLock.lock()
        guard !warmupScheduled, !scanRequested else { stateLock.unlock(); return }
        warmupScheduled = true
        stateLock.unlock()
        queue.async(qos: .utility) { [self] in
            stateLock.lock()
            let shouldWarmUp = !scanRequested
            stateLock.unlock()
            guard shouldWarmUp else { return }
            // Best effort: a failed warm-up must not surface sample text/errors
            // in the UI, or prevent the real request from trying normally.
            autoreleasepool { try? initializeEngine() }
        }
    }

    func recognize(data: Data, mode: OCRMode,
                   completion: @escaping (Result<OCRResult, Error>) -> Void) {
        stateLock.lock()
        scanRequested = true
        stateLock.unlock()
        queue.async(qos: .userInitiated) { [self] in
            let result = autoreleasepool { Result { try recognizeImage(data, mode) } }
            completion(result)
        }
    }
}
