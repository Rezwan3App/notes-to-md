// notes_ocr.swift
// Steps 1 and 2 of notes-to-md: prepare page images and recognize text, all on-device.
//
// Usage:
//   swift notes_ocr.swift <input file or folder> <output folder> [--threshold 0.5] [--long-side 2000] [--langs en-US,fr-FR]
//
// Input:  HEIC, HEIF, JPG, JPEG, PNG, TIFF images, or PDFs. A folder is processed in Finder name order.
// Output (in the output folder):
//   page-001.jpg   processed grayscale page
//   page-001.txt   recognized lines, top to bottom; low-confidence lines start with "[unclear] "
//   page-001.json  every line with its confidence score
//   manifest.json  per-page stats
// Originals are only read, never written.

import AppKit
import CoreImage
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

// MARK: - Arguments

struct Options {
    var input: URL
    var output: URL
    var threshold: Float = 0.5
    var longSide: CGFloat = 2000
    var langs: [String] = ["en-US"]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func parseOptions() -> Options {
    var args = Array(CommandLine.arguments.dropFirst())
    var positional: [String] = []
    var opts = Options(input: URL(fileURLWithPath: "/"), output: URL(fileURLWithPath: "/"))
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--threshold":
            guard let v = args.first.flatMap(Float.init) else { fail("--threshold needs a number") }
            opts.threshold = v; args.removeFirst()
        case "--long-side":
            guard let v = args.first.flatMap(Double.init) else { fail("--long-side needs a number") }
            opts.longSide = CGFloat(v); args.removeFirst()
        case "--langs":
            guard let v = args.first else { fail("--langs needs a value") }
            opts.langs = v.split(separator: ",").map(String.init); args.removeFirst()
        default:
            positional.append(a)
        }
    }
    guard positional.count == 2 else {
        fail("usage: notes_ocr.swift <input file or folder> <output folder> [--threshold 0.5] [--long-side 2000] [--langs en-US]")
    }
    opts.input = URL(fileURLWithPath: (positional[0] as NSString).expandingTildeInPath).standardizedFileURL
    opts.output = URL(fileURLWithPath: (positional[1] as NSString).expandingTildeInPath).standardizedFileURL
    return opts
}

// MARK: - Input discovery

let imageExts: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff"]

func collectInputs(_ url: URL) -> [URL] {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { fail("input not found: \(url.path)") }
    if !isDir.boolValue { return [url] }
    let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return items
        .filter { let e = $0.pathExtension.lowercased(); return imageExts.contains(e) || e == "pdf" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

// MARK: - Step 1: prepare images

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

struct PreparedPage {
    let image: CGImage
    let source: String
    let pdfPage: Int?
    let documentDetected: Bool
}

/// Finds the page in a photo and returns it flattened. Returns nil if no confident page is found.
func cropToDocument(_ image: CIImage) -> CIImage? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    guard (try? handler.perform([request])) != nil,
          let obs = request.results?.first,
          obs.confidence >= 0.5 else { return nil }

    let w = image.extent.width, h = image.extent.height
    func px(_ p: CGPoint) -> CIVector { CIVector(x: image.extent.minX + p.x * w, y: image.extent.minY + p.y * h) }

    // Skip tiny detections; a page that small is more likely a false hit than the note.
    let box = obs.boundingBox
    if box.width * box.height < 0.15 { return nil }

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(px(obs.topLeft), forKey: "inputTopLeft")
    filter.setValue(px(obs.topRight), forKey: "inputTopRight")
    filter.setValue(px(obs.bottomLeft), forKey: "inputBottomLeft")
    filter.setValue(px(obs.bottomRight), forKey: "inputBottomRight")
    return filter.outputImage
}

/// Shrinks to the long side limit and converts to an 8-bit grayscale CGImage.
func finish(_ image: CIImage, longSide: CGFloat) -> CGImage? {
    var img = image
    let longest = max(img.extent.width, img.extent.height)
    if longest > longSide {
        let scale = longSide / longest
        let f = CIFilter(name: "CILanczosScaleTransform")!
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(scale, forKey: kCIInputScaleKey)
        f.setValue(1.0, forKey: kCIInputAspectRatioKey)
        img = f.outputImage!
    }
    img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
    img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    let extent = img.extent.integral
    guard let rgb = ciContext.createCGImage(img, from: extent) else { return nil }

    let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
    guard let ctx = CGContext(data: nil, width: rgb.width, height: rgb.height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: rgb.width, height: rgb.height))
    ctx.draw(rgb, in: CGRect(x: 0, y: 0, width: rgb.width, height: rgb.height))
    return ctx.makeImage()
}

func prepareImage(_ url: URL, longSide: CGFloat) -> PreparedPage? {
    guard let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
    let cropped = cropToDocument(ci)
    guard let cg = finish(cropped ?? ci, longSide: longSide) else { return nil }
    return PreparedPage(image: cg, source: url.lastPathComponent, pdfPage: nil, documentDetected: cropped != nil)
}

/// Renders each PDF page on a white background. Scanned pages are already flat, so no document detection.
func preparePDF(_ url: URL, longSide: CGFloat) -> [PreparedPage] {
    guard let doc = PDFDocument(url: url) else { return [] }
    var pages: [PreparedPage] = []
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale = longSide / max(size.width, size.height)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let thumb = page.thumbnail(of: target, for: .mediaBox)
        guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let gray = finish(CIImage(cgImage: cg), longSide: longSide) else { continue }
        pages.append(PreparedPage(image: gray, source: url.lastPathComponent, pdfPage: i + 1, documentDetected: false))
    }
    return pages
}

func writeJPEG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

// MARK: - Step 2: recognize text

struct Line: Codable {
    let text: String
    let confidence: Float
    let unclear: Bool
}

func recognize(_ image: CGImage, opts: Options) -> [Line] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = opts.langs
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    guard (try? handler.perform([request])) != nil, let results = request.results else { return [] }

    // Vision uses a bottom-left origin, so a larger midY is higher on the page.
    // Lines whose centers sit within half a line height of each other count as the same row, read left to right.
    let sorted = results.sorted { a, b in
        let tolerance = min(a.boundingBox.height, b.boundingBox.height) / 2
        if abs(a.boundingBox.midY - b.boundingBox.midY) > tolerance { return a.boundingBox.midY > b.boundingBox.midY }
        return a.boundingBox.minX < b.boundingBox.minX
    }
    return sorted.compactMap { obs in
        guard let top = obs.topCandidates(1).first else { return nil }
        let text = top.string.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        return Line(text: text, confidence: top.confidence, unclear: top.confidence < opts.threshold)
    }
}

// MARK: - Main

struct PageStats: Codable {
    let page: Int
    let source: String
    let pdfPage: Int?
    let documentDetected: Bool
    let lines: Int
    let unclearLines: Int
    let meanConfidence: Float
    let mostlyUnreadable: Bool
    let textFile: String
}

struct Manifest: Codable {
    let input: String
    let threshold: Float
    let pages: [PageStats]
    let skipped: [String]
}

let opts = parseOptions()
let inputs = collectInputs(opts.input)
if inputs.isEmpty { fail("no supported files in \(opts.input.path)") }
try? FileManager.default.createDirectory(at: opts.output, withIntermediateDirectories: true)

var prepared: [PreparedPage] = []
var skipped: [String] = []
for url in inputs {
    if url.pathExtension.lowercased() == "pdf" {
        let pages = preparePDF(url, longSide: opts.longSide)
        if pages.isEmpty { skipped.append(url.lastPathComponent) }
        prepared += pages
    } else if let page = prepareImage(url, longSide: opts.longSide) {
        prepared.append(page)
    } else {
        skipped.append(url.lastPathComponent)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
var stats: [PageStats] = []

for (i, page) in prepared.enumerated() {
    let n = i + 1
    let base = String(format: "page-%03d", n)
    writeJPEG(page.image, to: opts.output.appendingPathComponent("\(base).jpg"))

    let lines = recognize(page.image, opts: opts)
    let text = lines.map { $0.unclear ? "[unclear] \($0.text)" : $0.text }.joined(separator: "\n")
    try? (text + "\n").write(to: opts.output.appendingPathComponent("\(base).txt"), atomically: true, encoding: .utf8)
    if let data = try? encoder.encode(lines) {
        try? data.write(to: opts.output.appendingPathComponent("\(base).json"))
    }

    let unclear = lines.filter(\.unclear).count
    let mean = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
    // "Mostly unreadable": nothing found, or at least half the lines fell under the threshold.
    let mostly = lines.isEmpty || Float(unclear) / Float(lines.count) >= 0.5
    stats.append(PageStats(page: n, source: page.source, pdfPage: page.pdfPage, documentDetected: page.documentDetected,
                           lines: lines.count, unclearLines: unclear, meanConfidence: mean,
                           mostlyUnreadable: mostly, textFile: "\(base).txt"))
}

let manifest = Manifest(input: opts.input.path, threshold: opts.threshold, pages: stats, skipped: skipped)
if let data = try? encoder.encode(manifest) {
    try? data.write(to: opts.output.appendingPathComponent("manifest.json"))
}

// Short summary for the caller. Kept compact on purpose: this is what Claude reads.
print("output: \(opts.output.path)")
for s in stats {
    let src = s.pdfPage.map { "\(s.source) p\($0)" } ?? s.source
    let flags = [s.documentDetected ? "cropped" : "full-frame", s.mostlyUnreadable ? "MOSTLY UNREADABLE" : nil]
        .compactMap { $0 }.joined(separator: ", ")
    print(String(format: "page %d  %@  lines=%d unclear=%d mean=%.2f  (%@)", s.page, src, s.lines, s.unclearLines, s.meanConfidence, flags))
}
if !skipped.isEmpty { print("skipped (could not open): \(skipped.joined(separator: ", "))") }
