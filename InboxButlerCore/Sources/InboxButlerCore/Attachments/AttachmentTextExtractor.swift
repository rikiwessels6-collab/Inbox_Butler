import Foundation
import PDFKit
import Vision
import ImageIO
import CoreGraphics

/// Turns an attachment's bytes into text, entirely on-device:
/// PDF (text layer, or OCR if scanned), images (Vision OCR), Word .docx, calendar files.
public struct AttachmentTextExtractor: Sendable {
    public enum ExtractionError: Error, LocalizedError, Sendable {
        case unsupported(String), unreadable, tooLarge
        public var errorDescription: String? {
            switch self {
            case .unsupported(let why): return why
            case .unreadable: return "couldn't be read."
            case .tooLarge: return "is too large to scan."
            }
        }
    }

    public static let maxBytes = 15_000_000
    static let maxPDFPages = 10
    static let maxOCRPages = 3

    public init() {}

    public func text(from data: Data, kind: AttachmentInfo.Kind, filename: String) async throws -> String {
        guard data.count <= Self.maxBytes else { throw ExtractionError.tooLarge }
        switch kind {
        case .pdf: return try await pdfText(data)
        case .image: return try await ocr(imageData: data)
        case .calendar: return String(decoding: data, as: UTF8.self)
        case .wordDocument:
            guard filename.lowercased().hasSuffix(".docx") else {
                throw ExtractionError.unsupported("is an old .doc file; only .docx is supported.")
            }
            do { return try DocxReader.text(from: data) } catch { throw ExtractionError.unreadable }
        case .other: throw ExtractionError.unsupported("is a file type that can't be scanned.")
        }
    }

    // MARK: PDF

    private func pdfText(_ data: Data) async throws -> String {
        guard let doc = PDFDocument(data: data) else { throw ExtractionError.unreadable }
        let pages = min(doc.pageCount, Self.maxPDFPages)
        var text = ""
        for i in 0..<pages { text += (doc.page(at: i)?.string ?? "") + "\n" }
        // Scanned PDFs have no text layer: fall back to OCR on the first pages.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            for i in 0..<min(pages, Self.maxOCRPages) {
                if let page = doc.page(at: i), let image = Self.render(page) {
                    text += try await ocr(cgImage: image, orientation: .up) + "\n"
                }
            }
        }
        return text
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0, let ref = page.pageRef else { return nil }
        let scale = min(2.0, 3000.0 / max(box.width, box.height))
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(ref)
        return ctx.makeImage()
    }

    // MARK: OCR

    private func ocr(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ExtractionError.unreadable }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return try await ocr(cgImage: image, orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }

    private func ocr(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch {
                    // The completion handler is not called when perform() throws.
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
