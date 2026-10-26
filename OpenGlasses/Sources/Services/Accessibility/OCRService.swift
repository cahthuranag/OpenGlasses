import Foundation
import Vision
import CoreGraphics
import UIKit

/// Reusable on-device OCR over Apple Vision. Privacy-first: images never leave the device.
///
/// Shared by the Reading Accessibility feature (A1) and Field Assist's `equipment_lookup` (reading
/// nameplates/error displays). Returns text in reading order plus per-block bounding boxes.
struct OCRService {

    struct Block: Equatable {
        let text: String
        let confidence: Float
        /// Vision-normalized bounding box (origin bottom-left, 0–1).
        let boundingBox: CGRect
    }

    struct Result: Equatable {
        let text: String
        let blocks: [Block]
        var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Minimum per-observation confidence to keep (0–1).
    var minimumConfidence: Float = 0.3

    init(minimumConfidence: Float = 0.3) {
        self.minimumConfidence = minimumConfidence
    }

    /// Recognize text in image data (e.g. a captured JPEG). Returns an empty result on failure.
    func recognizeText(in data: Data) async -> Result {
        guard let cgImage = UIImage(data: data)?.cgImage else { return Result(text: "", blocks: []) }
        return await recognizeText(in: cgImage)
    }

    /// Recognize text in a CGImage, sorted top-to-bottom then left-to-right (natural reading order).
    func recognizeText(in cgImage: CGImage) async -> Result {
        // Vision's Objective-C requests and observations must drain after each page, rather
        // than accumulating for the lifetime of a multi-thousand-page import task.
        autoreleasepool {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do { try handler.perform([request]) }
            catch {
                PrivacyLog.vision(.ocr, .recognitionFailed, error: SafeErrorSummary(error))
                return Result(text: "", blocks: [])
            }
            var blocks = (request.results ?? []).compactMap { observation -> Block? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= minimumConfidence else { return nil }
                return Block(text: candidate.string, confidence: candidate.confidence,
                             boundingBox: observation.boundingBox)
            }
            blocks.sort { a, b in
                if abs(a.boundingBox.maxY - b.boundingBox.maxY) < 0.02 { return a.boundingBox.minX < b.boundingBox.minX }
                return a.boundingBox.maxY > b.boundingBox.maxY
            }
            return Result(text: blocks.map(\.text).joined(separator: "\n"), blocks: blocks)
        }
    }
}
