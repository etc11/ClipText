import Foundation
import ImageIO
import Vision

enum OCRMode {
    case automatic
    case fast
    case accurate
}

struct OCRResult {
    let text: String
    let mode: OCRMode
    let warning: String?

    init(text: String, mode: OCRMode, warning: String? = nil) {
        self.text = text
        self.mode = mode
        self.warning = warning
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    case imageTooLarge
    case recognitionFailed(String)
    case multilingualUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This file couldn’t be read as an image. Try a PNG, JPEG, TIFF, or HEIC image."
        case .imageTooLarge: return "This image is too large. Try cropping it or exporting a smaller copy."
        case .recognitionFailed: return "macOS couldn’t start text recognition for this image. Try again. If it keeps failing, quit and reopen ClipText."
        case .multilingualUnavailable: return "macOS couldn’t start English/Chinese recognition. Try Read Again or reopen ClipText."
        }
    }
}

enum OCR {
    enum Attempt { case bilingual, compatibleBilingual, fast }

    static func recognize(data: Data, mode: OCRMode = .automatic) throws -> OCRResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw OCRError.invalidImage
        }
        guard width > 0, height > 0, Double(width) * Double(height) <= 80_000_000 else {
            throw OCRError.imageTooLarge
        }
        // Decode orientation, cap processing size, and flatten wide-color,
        // grayscale, or transparent inputs into a predictable sRGB bitmap.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: decoded.width + 32, height: decoded.height + 32,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw OCRError.invalidImage
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.draw(decoded, in: CGRect(x: 16, y: 16, width: decoded.width, height: decoded.height))
        guard let image = context.makeImage() else { throw OCRError.invalidImage }
        func perform(attempt: Attempt) throws -> String {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = attempt == .fast ? .fast : .accurate
            if attempt == .compatibleBilingual {
                // Public Vision revision 2 is a bilingual fallback on systems
                // where the newer accurate model fails to initialize.
                request.revision = 2
            }
            request.automaticallyDetectsLanguage = false
            if attempt == .fast {
                // Fast recognition supports fewer scripts. Don't reuse the
                // accurate pipeline's language detection configuration.
                let supported = try request.supportedRecognitionLanguages()
                let preferred = Locale.preferredLanguages.compactMap { language in
                    supported.first { $0.replacingOccurrences(of: "_", with: "-") == language }
                }
                request.recognitionLanguages = preferred.isEmpty ? ["en-US"] : preferred
            } else {
                // Chinese-first selects a model that also reads English. This
                // handles mixed text without a slow, fallible script-guessing
                // pass or silently discarding Chinese with English-only OCR.
                let supported = try request.supportedRecognitionLanguages()
                let languages = ["zh-Hans", "zh-Hant", "en-US"]
                guard languages.allSatisfy({ supported.contains($0) }) else {
                    throw OCRError.multilingualUnavailable
                }
                request.recognitionLanguages = languages
            }
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        return try recognize(mode: mode, perform: perform)
    }

    static func recognize(mode: OCRMode, perform: (Attempt) throws -> String) throws -> OCRResult {
        if mode != .fast {
            do {
                return OCRResult(text: try perform(.bilingual), mode: mode)
            } catch {
                do {
                    return OCRResult(text: try perform(.compatibleBilingual), mode: mode)
                } catch {
                    // Keep English OCR available on unsupported backends, but
                    // never present partial text as successful multilingual OCR.
                    if let text = try? perform(.fast), !text.isEmpty {
                        return OCRResult(text: text, mode: .fast,
                            warning: "Multilingual OCR is unavailable. This is an English-only result; Chinese text may be missing. Try Read Again, or run ClipText natively on an Apple silicon Mac.")
                    }
                    throw OCRError.multilingualUnavailable
                }
            }
        }
        do {
            return OCRResult(text: try perform(.fast), mode: .fast)
        } catch {
            throw OCRError.recognitionFailed(String(describing: error))
        }
    }
}
