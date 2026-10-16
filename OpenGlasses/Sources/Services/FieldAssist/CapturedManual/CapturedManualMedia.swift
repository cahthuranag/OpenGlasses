import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// All adapters are on-device. Called on a worker; no camera, frame or network is owned here.
enum CapturedManualMedia {
    static func jpeg(_ image: CGImage, longEdge: Int = 2200) throws -> Data {
        guard image.width > 0, image.height > 0, (1...2200).contains(longEdge) else { throw CapturedManualStore.Failure.invalidRequest }
        let scale = min(1, Double(longEdge) / Double(max(image.width,image.height)))
        let width = max(1,Int(Double(image.width)*scale));let height = max(1,Int(Double(image.height)*scale))
        guard let color = CGColorSpace(name:CGColorSpace.sRGB), let context = CGContext(data:nil,width:width,height:height,
            bitsPerComponent:8,bytesPerRow:0,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CapturedManualStore.Failure.unavailable
        }
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        guard let scaled = context.makeImage() else { throw CapturedManualStore.Failure.unavailable }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes,UTType.jpeg.identifier as CFString,1,nil) else {
            throw CapturedManualStore.Failure.unavailable
        }
        // No source EXIF, location or camera metadata is copied.
        CGImageDestinationAddImage(destination,scaled,[kCGImageDestinationLossyCompressionQuality:0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length <= CapturedManualContract.maximumImageBytes else {
            throw CapturedManualStore.Failure.limits
        }
        return bytes as Data
    }
    static func image(_ bytes: Data) throws -> CGImage {
        guard bytes.count <= CapturedManualContract.maximumImageBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData,nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...2200).contains(width), (1...2200).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {
            throw CapturedManualStore.Failure.missingPage
        }
        return image
    }
    static func languages(preferred: [String]) throws -> CapturedManualLanguages {
        let request = VNRecognizeTextRequest();request.recognitionLevel = .accurate
        return .resolve(preferred:preferred,supported:try request.supportedRecognitionLanguages())
    }
    static func recognize(_ bytes: Data, languages: [String], fallback: Bool) async throws -> CapturedManualAssembler.Reading {
        let request = VNRecognizeTextRequest();request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = fallback
        try VNImageRequestHandler(cgImage: image(bytes),orientation:.up).perform([request])
        let results = (request.results ?? []).compactMap { observation -> (String,Float,CGRect)? in
            guard let result = observation.topCandidates(1).first else { return nil }
            return (result.string,result.confidence,observation.boundingBox)
        }.sorted { lhs,rhs in
            abs(lhs.2.maxY-rhs.2.maxY) < 0.02 ? lhs.2.minX < rhs.2.minX : lhs.2.maxY > rhs.2.maxY
        }
        return .init(text:results.map(\.0).joined(separator:"\n"),
                     confidence:results.isEmpty ? 0 : results.reduce(0) { $0 + $1.1 } / Float(results.count))
    }
    static func pdf(_ draft: CapturedManualStore.Draft, imageAt: (Int) throws -> Data) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data:output) else { throw CapturedManualStore.Failure.unavailable }
        var box = CGRect(x:0,y:0,width:612,height:792)
        guard let context = CGContext(consumer:consumer,mediaBox:&box,
            [kCGPDFContextCreator as String:"Avenkin",kCGPDFContextTitle as String:draft.metadata.title] as CFDictionary)
        else { throw CapturedManualStore.Failure.unavailable }
        for index in 1...draft.images.count {
            try Task.checkCancellation()
            try autoreleasepool {
                let image = try image(imageAt(index))
                var pageBox = CGRect(x:0,y:0,width:Double(image.width)*72/200,height:Double(image.height)*72/200)
                let rect = NSData(bytes:&pageBox,length:MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String:rect] as CFDictionary)
                context.draw(image,in:pageBox);context.endPDFPage()
                guard output.length <= CapturedManualContract.maximumPDFBytes else { throw CapturedManualStore.Failure.limits }
            }
        }
        context.closePDF()
        guard let document = PDFDocument(data:output as Data) else { throw CapturedManualStore.Failure.unavailable }
        // Pin both dates to the source revision. Persist this result before OCR; PDFKit's
        // internal object ids are not assumed reproducible on another process/OS release.
        let date = Date(timeIntervalSince1970:TimeInterval(draft.metadata.capturedAt))
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute:draft.metadata.title,PDFDocumentAttribute.creatorAttribute:"Avenkin",
                                       PDFDocumentAttribute.creationDateAttribute:date,PDFDocumentAttribute.modificationDateAttribute:date]
        guard let bytes = document.dataRepresentation(), bytes.count <= CapturedManualContract.maximumPDFBytes else {
            throw CapturedManualStore.Failure.limits
        }
        return try pinDates(bytes,to:date)
    }
    /// Some PDFKit releases rewrite Info dates during serialization, ignoring the attributes
    /// above. Patch only the two unique date literals in our own unencrypted encoder output,
    /// preserving their byte widths so every cross-reference offset remains valid. Ambiguous
    /// or changed encoder output fails closed, and the final parsed dates must verify.
    static func pinDates(_ data:Data,to date:Date) throws -> Data {
        let formatter = DateFormatter();formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.calendar = Calendar(identifier:.gregorian);formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        let digits = Data(formatter.string(from:date).utf8)
        guard digits.count == 14 else {throw CapturedManualStore.Failure.unavailable}
        var bytes = data
        for key in ["/CreationDate","/ModDate"] {
            let name = Data(key.utf8)
            guard let field = bytes.range(of:name),
                  bytes.range(of:name,in:field.upperBound..<bytes.endIndex) == nil else {throw CapturedManualStore.Failure.unavailable}
            var start = field.upperBound
            while start < bytes.endIndex && [9,10,12,13,32].contains(bytes[start]) {start += 1}
            guard start < bytes.endIndex,bytes[start] == 40 else {throw CapturedManualStore.Failure.unavailable}
            start += 1
            guard let end = bytes[start...].firstIndex(of:41),end - start <= 32 else {throw CapturedManualStore.Failure.unavailable}
            let original = bytes.subdata(in:start..<end)
            guard original.count >= 16,original.prefix(2) == Data("D:".utf8),
                  original.dropFirst(2).prefix(14).allSatisfy({(48...57).contains($0)}),
                  original.dropFirst(16).allSatisfy({(48...57).contains($0) || [90,43,45,39].contains($0)}) else {throw CapturedManualStore.Failure.unavailable}
            // Retain the encoder's timezone spelling/width, but make it UTC for the frozen digits.
            let suffix = original.dropFirst(16).map {(48...57).contains($0) ? UInt8(48) : $0}
            bytes.replaceSubrange(start..<end,with:Data("D:".utf8) + digits + Data(suffix))
        }
        guard bytes.count == data.count,let verified = PDFDocument(data:bytes),
              [PDFDocumentAttribute.creationDateAttribute,.modificationDateAttribute].allSatisfy({ key in
                  guard let saved = verified.documentAttributes?[key] as? Date else {return false}
                  return abs(saved.timeIntervalSince(date)) < 1
              }) else {throw CapturedManualStore.Failure.unavailable}
        return bytes
    }
    static func pageCount(_ bytes: Data) throws -> Int {
        guard bytes.count <= CapturedManualContract.maximumPDFBytes, let provider = CGDataProvider(data:bytes as CFData),
              let pdf = CGPDFDocument(provider) else { throw CapturedManualStore.Failure.missingPage }
        return pdf.numberOfPages
    }
}
