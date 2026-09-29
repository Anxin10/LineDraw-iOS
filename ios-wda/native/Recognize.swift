import Foundation
import Vision
import ImageIO

struct TextRegion: Codable {
    let text: String
    let confidence: Float
    let x, y, width, height: Double
}
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: recognize screenshot.png\n", stderr)
    exit(2)
}
do {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hant", "en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]), options: [:])
    try handler.perform([request])
    let regions = (request.results ?? []).compactMap { observation -> TextRegion? in
        guard let result = observation.topCandidates(1).first else { return nil }
        let r = observation.boundingBox
        // Vision uses a bottom-left origin. Appium uses a top-left point coordinate space.
        return TextRegion(text: result.string, confidence: result.confidence,
                          x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
    FileHandle.standardOutput.write(try JSONEncoder().encode(regions))
} catch {
    fputs("Vision failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
