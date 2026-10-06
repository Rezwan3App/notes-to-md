// notes_ocr.swift
// Steps 1 and 2 of notes-to-md: prepare page images and recognize text, all on-device. English only.
//
// Usage (the notes-ocr wrapper next to this file compiles it once and caches the binary):
//   notes-ocr <input file or folder> [output folder] [--no-text] [--threshold 0.5] [--long-side 2000] [--no-spellcheck]
//   Without an output folder, a new temp folder is made and its path printed.
//   After the summary it prints every page's text, so the caller needs no second read. Pages with no
//   text are left out of that part. --no-text prints the summary only.
//   swift notes_ocr.swift <same arguments>
//
// Input:  HEIC, HEIF, JPG, JPEG, PNG, TIFF images, or PDFs. A folder is processed in Finder name order.
//         Other files in the folder are listed as ignored. Subfolders are not searched.
// Output (in the output folder, which must be new, empty, or an earlier output folder of this script):
//   page-001.jpg   processed grayscale page
//   page-001.txt   recognized lines in reading order; doubtful lines start with "[unclear] "
//   page-001.json  every line with its confidence score, the words the spell checker did not know, and its box
//   manifest.json  per-page stats
// Pages left over from an earlier run in the same output folder are deleted first.
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
    // With language correction on, Vision only reports confidences of 0.3, 0.5 or 1.0, and misread words
    // often get 1.0. So 0.5 tags only the 0.3 lines; the spell check below does most of the work.
    var threshold: Float = 0.5
    var longSide: CGFloat = 2000
    var spellCheck = true
    var printText = true
    var madeOutput = false
}

let usage = "usage: notes-ocr <input file or folder> [output folder] [--no-text] [--threshold 0.5] [--long-side 2000] [--no-spellcheck]"

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
            guard let v = args.first.flatMap(Float.init), v >= 0, v <= 1 else { fail("--threshold needs a number from 0 to 1") }
            opts.threshold = v; args.removeFirst()
        case "--long-side":
            guard let v = args.first.flatMap(Double.init), v >= 200, v <= 10000 else { fail("--long-side needs a number from 200 to 10000") }
            opts.longSide = CGFloat(v); args.removeFirst()
        case "--no-spellcheck":
            opts.spellCheck = false
        case "--text":
            opts.printText = true   // the default; kept so older commands still work
        case "--no-text":
            opts.printText = false
        default:
            if a.hasPrefix("--") { fail("unknown option \(a)\n\(usage)") }
            positional.append(a)
        }
    }
    guard positional.count == 1 || positional.count == 2 else { fail(usage) }
    func url(_ s: String) -> URL {
        URL(fileURLWithPath: (s as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
    }
    opts.input = url(positional[0])
    if positional.count == 2 {
        opts.output = url(positional[1])
    } else {
        let name = "notes-to-md-" + UUID().uuidString.prefix(8)
        opts.output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name).resolvingSymlinksInPath()
        opts.madeOutput = true
    }
    return opts
}

// MARK: - Input discovery

let imageExts: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff"]

/// Returns the files to process in order, plus the names of files that were left out because of their type.
func collectInputs(_ url: URL) -> (files: [URL], ignored: [String]) {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { fail("input not found: \(url.path)") }
    if !isDir.boolValue {
        let e = url.pathExtension.lowercased()
        guard imageExts.contains(e) || e == "pdf" else { fail("not a supported file type (HEIC, JPG, PNG, TIFF, or PDF): \(url.path)") }
        return ([url], [])
    }
    let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                               options: [.skipsHiddenFiles])) ?? []
    // Subfolders (and anything else that isn't a regular file, like a directory named "scan.jpg")
    // are never searched, but still get reported as ignored so they don't just vanish.
    // Resolve first: URL resource values don't follow symlinks, so a linked photo would read as "not a file".
    let isFile = { (u: URL) in (try? u.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    let files = items.filter(isFile)
    let nonFiles = items.filter { !isFile($0) }
    let wanted = files.filter { let e = $0.pathExtension.lowercased(); return imageExts.contains(e) || e == "pdf" }
    let byName: (URL, URL) -> Bool = { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    let ignored = (files.filter { !wanted.contains($0) } + nonFiles).sorted(by: byName).map(\.lastPathComponent)
    return (wanted.sorted(by: byName), ignored)
}

/// Makes the output folder ready. Refuses a folder that holds anything this script did not write, so user
/// files are never deleted or mixed in. Old page files from an earlier run are removed.
func prepareOutput(_ out: URL, input: URL) {
    let fm = FileManager.default
    let inputDir = (try? input.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? input : input.deletingLastPathComponent()
    if out.path == inputDir.path { fail("the output folder must not be the input folder: \(out.path)") }
    let markerName = ".notes-ocr-tmp"
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: out.path, isDirectory: &isDir) {
        guard isDir.boolValue else { fail("output path is a file, not a folder: \(out.path)") }
        let names = (try? fm.contentsOfDirectory(atPath: out.path)) ?? []
        // The marker proves an earlier run made this folder; the name pattern limits what gets deleted.
        // Both are needed: a name match alone could hit a user's own manifest.json, and a marker alone
        // would wipe files the user saved into the folder after that run.
        guard names.contains(markerName) else {
            let visible = names.filter { $0 != ".DS_Store" }
            if !visible.isEmpty {
                fail("output folder already has other files (\(visible.prefix(3).joined(separator: ", "))). Use a new or empty folder: \(out.path)")
            }
            if !fm.createFile(atPath: out.appendingPathComponent(markerName).path, contents: nil) {
                fail("could not prepare output folder \(out.path)")
            }
            return
        }
        let ours = try! NSRegularExpression(pattern: "^(page-[0-9]{3,}\\.(jpg|txt|json)|manifest\\.json|\\.DS_Store|\\.notes-ocr-tmp)$")
        let foreign = names.filter { ours.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) == nil }
        if !foreign.isEmpty {
            fail("output folder already has other files (\(foreign.prefix(3).joined(separator: ", "))). Use a new or empty folder: \(out.path)")
        }
        for n in names where n != ".DS_Store" && n != markerName {
            do { try fm.removeItem(at: out.appendingPathComponent(n)) } catch { fail("could not clear old output file \(n): \(error.localizedDescription)") }
        }
    } else {
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
        } catch {
            fail("could not create output folder \(out.path): \(error.localizedDescription)")
        }
        if !fm.createFile(atPath: out.appendingPathComponent(markerName).path, contents: nil) {
            fail("could not prepare output folder \(out.path)")
        }
    }
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
    guard let out = filter.outputImage, out.extent.width >= 32, out.extent.height >= 32 else { return nil }
    return out
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
    guard extent.width >= 1, extent.height >= 1, let rgb = ciContext.createCGImage(img, from: extent) else { return nil }

    let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
    guard let ctx = CGContext(data: nil, width: rgb.width, height: rgb.height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: rgb.width, height: rgb.height))
    ctx.draw(rgb, in: CGRect(x: 0, y: 0, width: rgb.width, height: rgb.height))
    return ctx.makeImage()
}

func prepareImage(_ url: URL, longSide: CGFloat) -> PreparedPage? {
    guard let raw = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
          !raw.extent.isInfinite, raw.extent.width >= 1, raw.extent.height >= 1 else { return nil }
    // Put see-through images (PNG with transparency) on white first, so the page finder sees paper, not black.
    let ci = raw.composited(over: CIImage(color: .white).cropped(to: raw.extent))
    let cropped = cropToDocument(ci)
    guard let cg = finish(cropped ?? ci, longSide: longSide) else { return nil }
    return PreparedPage(image: cg, source: url.lastPathComponent, pdfPage: nil, documentDetected: cropped != nil)
}

/// Renders each PDF page on a white background and hands it to `each`. Scanned pages are already flat, so
/// no document detection. Returns nil if the PDF did not open. Otherwise returns how many pages rendered
/// and the 1-based numbers of pages that did not, so a partly broken PDF doesn't silently lose pages.
func preparePDF(_ url: URL, longSide: CGFloat, each: (PreparedPage) -> Void) -> (count: Int, failed: [Int])? {
    guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
    var count = 0
    var failed: [Int] = []
    for i in 0..<doc.pageCount {
        autoreleasepool {
            guard let page = doc.page(at: i) else { failed.append(i + 1); return }
            let bounds = page.bounds(for: .mediaBox)
            let rotated = page.rotation % 180 != 0
            let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
            guard size.width > 0, size.height > 0 else { failed.append(i + 1); return }
            let scale = longSide / max(size.width, size.height)
            let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
            let thumb = page.thumbnail(of: target, for: .mediaBox)
            guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let gray = finish(CIImage(cgImage: cg), longSide: longSide) else { failed.append(i + 1); return }
            count += 1
            each(PreparedPage(image: gray, source: url.lastPathComponent, pdfPage: i + 1, documentDetected: false))
        }
    }
    return (count, failed)
}

func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Step 2: recognize text

struct Line: Codable {
    let text: String
    let confidence: Float
    let unclear: Bool
    let suspectWords: [String]
    let box: [Double]   // minX, minY, maxX, maxY on the page, 0...1, origin bottom left
}

/// One piece of text as Vision found it. Coordinates are 0...1 with the origin at the bottom left.
struct Fragment {
    let text: String
    let confidence: Float
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
    let leftMidY: CGFloat   // vertical middle of the left edge
    let rightMidY: CGFloat  // vertical middle of the right edge
    let height: CGFloat     // text height, measured along the slant of the text
}

typealias TextLine = [Fragment]

/// Joins fragments into lines.
///
/// Vision often splits one handwritten line into several pieces. Two pieces are joined when the second
/// starts where the first one ends: its left edge sits at the height of the first piece's right edge
/// (within half a text height, so slanted lines still join) and the space between them is at most
/// 2 text heights, or 4 when either side of the space is an arrow. Pieces farther apart stay separate
/// lines. That keeps a margin note next to a main line from being glued onto it.
func joinFragments(_ frags: [Fragment], width: CGFloat, height: CGFloat) -> [TextLine] {
    func isArrow(_ s: String, atStart: Bool) -> Bool {
        let marks = ["\u{2192}", "->", "=>"]
        return marks.contains { atStart ? s.hasPrefix($0) : s.hasSuffix($0) }
    }
    var links: [(cost: CGFloat, a: Int, b: Int)] = []
    for a in frags.indices {
        for b in frags.indices where a != b && frags[b].minX > frags[a].minX {
            let A = frags[a], B = frags[b]
            let h = max(A.height, B.height) * height
            guard h > 0 else { continue }
            let gap = (B.minX - A.maxX) * width
            let arrow = isArrow(A.text, atStart: false) || isArrow(B.text, atStart: true)
            guard gap >= -0.5 * h, gap <= (arrow ? 4 : 2) * h else { continue }
            let dy = abs(A.rightMidY - B.leftMidY) * height
            guard dy <= 0.5 * h else { continue }
            links.append((dy / h + max(gap, 0) / h * 0.1, a, b))
        }
    }
    // Best links first. Each piece gets at most one piece after it and one before it.
    links.sort { ($0.cost, $0.a, $0.b) < ($1.cost, $1.a, $1.b) }
    var next: [Int: Int] = [:], prev: [Int: Int] = [:]
    for l in links where next[l.a] == nil && prev[l.b] == nil {
        next[l.a] = l.b; prev[l.b] = l.a
    }
    var lines: [TextLine] = []
    for i in frags.indices where prev[i] == nil {
        var chain = [i]
        while let n = next[chain.last!], chain.count <= frags.count { chain.append(n) }
        lines.append(chain.map { frags[$0] })
    }
    return lines
}

/// Puts lines in reading order: lines whose starts are within half a text height of each other form one
/// row and are read left to right. Rows go top to bottom. A short note beside a main line comes out as
/// its own line right after it.
func readingOrder(_ lines: [TextLine]) -> [TextLine] {
    // Sorting on one key (the line's starting height) keeps the order well defined.
    let sorted = lines.sorted { ($0[0].leftMidY, -$0[0].minX) > ($1[0].leftMidY, -$1[0].minX) }
    var rows: [[TextLine]] = []
    for c in sorted {
        if let first = rows.last?.first {
            let hs = first.map(\.height).sorted()
            if first[0].leftMidY - c[0].leftMidY < 0.5 * hs[hs.count / 2] {
                rows[rows.count - 1].append(c); continue
            }
        }
        rows.append([c])
    }
    return rows.flatMap { $0.sorted { $0[0].minX < $1[0].minX } }
}

/// Finds two columns of text and returns them read one after the other: lines above the columns that
/// span both (a title), the whole left column, the whole right column, then lines below that span both.
/// Returns nil for a one-column page.
///
/// A page counts as two columns only when there is an empty vertical strip (no line crosses it) in the
/// middle half of the text, and each side:
///   - has at least 3 lines, and at least half as many lines as the other side
///   - covers most of the column height and is at least half as wide as the other side
///   - has lines that mostly fill its width
///   - has most lines level with a line on the other side
/// A few margin notes, indented lines, or short labels with notes beside them fail these tests, so
/// ordinary notes keep the row by row order. Columns whose rows do not line up (unruled paper) are
/// also left in row order.
func splitColumns(_ lines: [TextLine], width: CGFloat, height: CGFloat) -> [TextLine]? {
    guard lines.count >= 6 else { return nil }
    struct Box { let minX, maxX, minY, maxY: CGFloat; var midY: CGFloat { (minY + maxY) / 2 } }
    let boxes = lines.map { l in
        Box(minX: l.map(\.minX).min()! * width, maxX: l.map(\.maxX).max()! * width,
            minY: l.map(\.minY).min()! * height, maxY: l.map(\.maxY).max()! * height)
    }
    let lo = boxes.map(\.minX).min()!, hi = boxes.map(\.maxX).max()!
    let hs = lines.flatMap { $0.map { $0.height * height } }.sorted()
    let textH = hs[hs.count / 2]
    guard hi - lo > 4 * textH else { return nil }

    struct Split { let left: [Int]; let right: [Int]; let above: [Int]; let below: [Int]; let gutter: CGFloat }
    func test(_ x: CGFloat) -> Split? {
        let crossing = boxes.indices.filter { boxes[$0].minX < x && boxes[$0].maxX > x }
        let left = boxes.indices.filter { boxes[$0].maxX <= x }
        let right = boxes.indices.filter { boxes[$0].minX >= x }
        let cols = left + right
        // Both sides need a fair share of the lines. A few margin notes beside a long column do not count.
        guard left.count >= 3, right.count >= 3,
              Double(min(left.count, right.count)) >= 0.5 * Double(max(left.count, right.count)) else { return nil }
        let top = cols.map { boxes[$0].maxY }.max()!, bottom = cols.map { boxes[$0].minY }.min()!
        // Lines that cross the strip are allowed only above or below both columns, like a title.
        let above = crossing.filter { boxes[$0].midY > top }
        let below = crossing.filter { boxes[$0].midY < bottom }
        guard above.count + below.count == crossing.count, crossing.count <= cols.count / 3 else { return nil }
        // The empty strip must be at least one text height wide.
        let gutter = right.map { boxes[$0].minX }.min()! - left.map { boxes[$0].maxX }.max()!
        guard gutter >= textH else { return nil }
        let span = top - bottom
        for side in [left, right] {
            let sTop = side.map { boxes[$0].maxY }.max()!, sBottom = side.map { boxes[$0].minY }.min()!
            guard sTop - sBottom >= 0.6 * span else { return nil }
        }
        // Lines of a real column fill most of its width. Short labels with notes beside them (a table) do not.
        let leftEdge = left.map { boxes[$0].minX }.min()!, rightEdge = right.map { boxes[$0].maxX }.max()!
        let leftW = left.map { boxes[$0].maxX }.max()! - leftEdge, rightW = rightEdge - right.map { boxes[$0].minX }.min()!
        let lw = left.map { boxes[$0].maxX - boxes[$0].minX }.sorted(), rw = right.map { boxes[$0].maxX - boxes[$0].minX }.sorted()
        guard lw[lw.count / 2] >= 0.5 * leftW, rw[rw.count / 2] >= 0.5 * rightW else { return nil }
        // Columns are about the same width. Margin notes make a narrow strip beside a wide one.
        guard min(leftW, rightW) >= 0.5 * max(leftW, rightW) else { return nil }
        // Columns sit side by side: most lines have a line on the other side at the same height. In an
        // indented list, the indented lines sit between the outer ones instead.
        func besideCount(_ a: [Int], _ b: [Int]) -> Int {
            a.filter { i in b.contains { j in min(boxes[i].maxY, boxes[j].maxY) > max(boxes[i].minY, boxes[j].minY) } }.count
        }
        let fewer = left.count <= right.count ? (left, right) : (right, left)
        guard Double(besideCount(fewer.0, fewer.1)) >= 0.6 * Double(fewer.0.count) else { return nil }
        return Split(left: left, right: right, above: above, below: below, gutter: gutter)
    }
    // Try strips across the middle half of the text and keep the widest one that passes.
    var best: Split?
    for step in 0...100 {
        let x = lo + (hi - lo) * (0.25 + 0.5 * CGFloat(step) / 100)
        if let s = test(x), s.gutter > (best?.gutter ?? 0) { best = s }
    }
    guard let s = best else { return nil }
    let pick = { (idx: [Int]) in joinWrapped(readingOrder(idx.map { lines[$0] }), width: width, height: height) }
    return pick(s.above) + pick(s.left) + pick(s.right) + pick(s.below)
}

/// Words the macOS English dictionary does not know. Vision's confidence is often 1.0 on misread words
/// like "Micuosot", but those are rarely real words, so this catches most misreads.
func suspectWords(_ text: String, language: String?) -> [String] {
    guard let language else { return [] }
    let checker = NSSpellChecker.shared
    let ns = text as NSString
    var found: [String] = []
    var start = 0
    while start < ns.length {
        let r = checker.checkSpelling(of: text, startingAt: start, language: language, wrap: false,
                                      inSpellDocumentWithTag: 0, wordCount: nil)
        if r.location == NSNotFound || r.length == 0 { break }
        found.append(ns.substring(with: r))
        start = r.location + r.length
    }
    return found
}

/// Joins lines that wrap: a line that starts with a lowercase letter, right below a line that has no
/// end mark (. ? ! :), and starts inside that line's left to right span, is the rest of that line.
/// The line above must also be long (at least 60% as wide as the widest line) and reach the right edge
/// of the nearby text (within 3 text heights), since a line only wraps when it runs out of room. Nearby
/// text means lines within 5 text heights up or down that start left of where the line above ends, so a
/// margin note further right does not count. The lower line may not reach further right than the
/// line above, because that line ran out of room. That keeps short list items without bullets ("green apples", "ripe
/// bananas") apart. Call it on one column at a time.
/// "The books don't mention how to handle the" + "unexpected." becomes one line. A line starting with
/// a capital, number, arrow, dash, or bullet is never joined, so lists keep their items.
/// Only the 4 lines before it are checked, so a margin note between the two does not block the join.
func joinWrapped(_ lines: [TextLine], width: CGFloat, height: CGFloat) -> [TextLine] {
    struct Box { let minX, maxX, minY, maxY: CGFloat; var midY: CGFloat { (minY + maxY) / 2 } }
    func box(_ l: TextLine) -> Box {
        Box(minX: l.map(\.minX).min()! * width, maxX: l.map(\.maxX).max()! * width,
            minY: l.map(\.minY).min()! * height, maxY: l.map(\.maxY).max()! * height)
    }
    let boxes = lines.map(box)
    let widest = boxes.map { $0.maxX - $0.minX }.max() ?? 0
    var out: [TextLine] = []
    for line in lines {
        let text = line.map(\.text).joined(separator: " ")
        let b = box(line)
        var best: (index: Int, gap: CGFloat)?
        if let first = text.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) {
            for i in out.indices.suffix(4) {
                let above = out[i]
                guard let last = above.last?.text.last, !".?!:".contains(last) else { continue }
                let a = box(above)
                let hs = above.map { $0.height * height }.sorted()
                let h = hs[hs.count / 2]
                let gap = a.minY - b.maxY   // space between the two lines
                guard gap >= -0.5 * h, gap <= 1.2 * h, b.minX >= a.minX - h, b.minX <= a.maxX - h else { continue }
                // A line that wrapped ran out of room, so the rest of it cannot reach further right.
                guard b.maxX <= a.maxX + h else { continue }
                // The line above must be long and reach the right edge of the text near it.
                let near = boxes.filter { abs($0.midY - a.midY) <= 5 * h && $0.minX < a.maxX }
                let nearRight = near.map(\.maxX).max() ?? a.maxX
                guard a.maxX - a.minX >= 0.6 * widest, a.maxX >= nearRight - 3 * h else { continue }
                if gap < (best?.gap ?? .infinity) { best = (i, gap) }
            }
        }
        if let found = best { out[found.index] += line } else { out.append(line) }
    }
    return out
}

struct Recognized { let lines: [Line]; let columns: Int }

/// Returns nil if Vision failed. A page with no text gives no lines.
func recognize(_ image: CGImage, opts: Options, spellLanguage: String?) -> Recognized? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do { try handler.perform([request]) } catch {
        FileHandle.standardError.write("text recognition failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        return nil
    }
    let frags: [Fragment] = (request.results ?? []).compactMap { obs in
        guard let top = obs.topCandidates(1).first else { return nil }
        let text = top.string.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        let b = obs.boundingBox
        return Fragment(text: text, confidence: top.confidence, minX: b.minX, maxX: b.maxX, minY: b.minY, maxY: b.maxY,
                        leftMidY: (obs.topLeft.y + obs.bottomLeft.y) / 2,
                        rightMidY: (obs.topRight.y + obs.bottomRight.y) / 2,
                        height: max(abs(obs.topLeft.y - obs.bottomLeft.y), abs(obs.topRight.y - obs.bottomRight.y)))
    }
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let joined = joinFragments(frags, width: w, height: h)
    let columns = splitColumns(joined, width: w, height: h)
    let ordered = columns ?? joinWrapped(readingOrder(joined), width: w, height: h)
    let lines = ordered.map { parts in
        let text = parts.map(\.text).joined(separator: " ")
        let conf = parts.map(\.confidence).min() ?? 0
        let suspects = suspectWords(text, language: spellLanguage)
        let box = [parts.map(\.minX).min()!, parts.map(\.minY).min()!, parts.map(\.maxX).max()!, parts.map(\.maxY).max()!]
            .map { (Double($0) * 1000).rounded() / 1000 }
        return Line(text: text, confidence: conf, unclear: conf < opts.threshold || !suspects.isEmpty,
                    suspectWords: suspects, box: box)
    }
    return Recognized(lines: lines, columns: columns == nil ? 1 : 2)
}

// MARK: - Main

struct PageStats: Codable {
    let page: Int
    let source: String
    let pdfPage: Int?
    let documentDetected: Bool
    let columns: Int
    let lines: Int
    let unclearLines: Int
    let meanConfidence: Float
    let noText: Bool
    let mostlyUnreadable: Bool
    let recognitionFailed: Bool
    let textFile: String
}

struct Manifest: Codable {
    let input: String
    let threshold: Float
    let spellCheck: Bool
    let pages: [PageStats]
    let skipped: [String]
    let ignored: [String]
}

let opts = parseOptions()
let (inputs, ignored) = collectInputs(opts.input)
if inputs.isEmpty {
    fail("no supported files (HEIC, JPG, PNG, TIFF, or PDF) in \(opts.input.path)"
         + (ignored.isEmpty ? "" : "\nignored: \(ignored.joined(separator: ", "))"))
}
prepareOutput(opts.output, input: opts.input)

// Spell check needs the English dictionary. Without it, only the confidence score marks lines unclear.
let available = NSSpellChecker.shared.availableLanguages
let spellLanguage: String? = opts.spellCheck ? ["en_US", "en"].first(where: available.contains) : nil

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
var stats: [PageStats] = []
var skipped: [String] = []
var pageTexts: [String] = []

// A write failure here is almost always transient (disk full, permission hiccup) and can hit any
// single page in a long-running batch. Recording the page as skipped and moving on keeps the pages
// already processed, instead of a late page's write error throwing away the whole run's output.
func pageName(_ page: PreparedPage) -> String { page.pdfPage.map { "\(page.source) page \($0)" } ?? page.source }

func process(_ page: PreparedPage) {
    let n = stats.count + 1
    let base = String(format: "page-%03d", n)
    let out = opts.output
    guard writeJPEG(page.image, to: out.appendingPathComponent("\(base).jpg")) else {
        skipped.append(pageName(page))
        return
    }

    let result = recognize(page.image, opts: opts, spellLanguage: spellLanguage)
    let lines = result?.lines ?? []
    let text = lines.map { $0.unclear ? "[unclear] \($0.text)" : $0.text }.joined(separator: "\n")
    do {
        try (text + "\n").write(to: out.appendingPathComponent("\(base).txt"), atomically: true, encoding: .utf8)
        try encoder.encode(lines).write(to: out.appendingPathComponent("\(base).json"))
    } catch {
        // Don't leave a page image with no text beside it.
        try? FileManager.default.removeItem(at: out.appendingPathComponent("\(base).jpg"))
        skipped.append(pageName(page))
        return
    }

    pageTexts.append(text)
    let unclear = lines.filter(\.unclear).count
    let mean = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
    // "Mostly unreadable": at least half the words are doubtful. Counted by word, not by line, because one
    // misread word tags a whole line. A word is doubtful when its line's confidence is low (the whole line's
    // word count, since suspect words are always a subset of it) or, for a confident line, when the spell
    // check did not know it. A page with no text at all is reported separately.
    let words = lines.map { $0.text.split(separator: " ").count }.reduce(0, +)
    let doubtful = lines.map { $0.confidence < opts.threshold ? $0.text.split(separator: " ").count : $0.suspectWords.count }.reduce(0, +)
    let mostly = words > 0 && Float(doubtful) / Float(words) >= 0.5
    stats.append(PageStats(page: n, source: page.source, pdfPage: page.pdfPage, documentDetected: page.documentDetected,
                           columns: result?.columns ?? 1, lines: lines.count, unclearLines: unclear, meanConfidence: mean,
                           noText: result != nil && lines.isEmpty, mostlyUnreadable: mostly,
                           recognitionFailed: result == nil, textFile: "\(base).txt"))
}

// One page at a time, so a big folder or PDF never holds every page in memory.
for url in inputs {
    autoreleasepool {
        if url.pathExtension.lowercased() == "pdf" {
            guard let result = preparePDF(url, longSide: opts.longSide, each: process) else {
                skipped.append(url.lastPathComponent)
                return
            }
            if result.count == 0 {
                skipped.append(url.lastPathComponent)
            } else {
                for page in result.failed { skipped.append("\(url.lastPathComponent) page \(page)") }
            }
        } else if let page = prepareImage(url, longSide: opts.longSide) {
            process(page)
        } else {
            skipped.append(url.lastPathComponent)
        }
    }
}

let manifest = Manifest(input: opts.input.path, threshold: opts.threshold, spellCheck: spellLanguage != nil,
                        pages: stats, skipped: skipped, ignored: ignored)
do { try encoder.encode(manifest).write(to: opts.output.appendingPathComponent("manifest.json")) } catch {
    fail("could not write manifest.json: \(error.localizedDescription)")
}

// Short summary for the caller. Kept compact on purpose: this is what Claude reads.
for s in stats {
    let src = s.pdfPage.map { "\(s.source) p\($0)" } ?? s.source
    let flags = [s.documentDetected ? "cropped" : "full-frame",
                 s.columns == 2 ? "2 columns" : nil,
                 s.noText ? "NO TEXT FOUND" : nil,
                 s.mostlyUnreadable ? "MOSTLY UNREADABLE" : nil,
                 s.recognitionFailed ? "RECOGNITION FAILED" : nil]
        .compactMap { $0 }.joined(separator: ", ")
    print("page \(s.page)  \(src)  lines=\(s.lines) unclear=\(s.unclearLines) mean=\(String(format: "%.2f", s.meanConfidence))  (\(flags))")
}
if !skipped.isEmpty { print("skipped (could not open): \(skipped.joined(separator: ", "))") }
if !ignored.isEmpty { print("ignored (not a supported type): \(ignored.joined(separator: ", "))") }
if stats.isEmpty { fail("none of the files could be opened") }
if opts.madeOutput { print("work folder: \(opts.output.path)") }
if opts.printText {
    // Pages with no text are already flagged above, so their empty text is not printed.
    for (i, t) in pageTexts.enumerated() where stats[i].lines > 0 { print("\n--- page \(i + 1) ---\n\(t)") }
}
