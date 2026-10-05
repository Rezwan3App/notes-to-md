// make_fixtures.swift: draws synthetic note pages for run_tests.sh.
// Usage: swift make_fixtures.swift <output folder>
// Text is drawn in a handwriting-style font on white paper, some pages on a dark desk and slightly turned.

import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

struct Text { let s: String; let x: CGFloat; let y: CGFloat }   // x, y: fraction of the paper, y from the top

/// Draws a page. With `desk`, the paper sits on a dark background and is turned by `angle` degrees.
func page(w: Int, h: Int, texts: [Text], size: CGFloat, desk: Bool = false, angle: CGFloat = 0,
          clear: Bool = false, font: String = "Noteworthy-Bold") -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let pw = desk ? CGFloat(w) * 0.8 : CGFloat(w), ph = desk ? CGFloat(h) * 0.8 : CGFloat(h)
    if desk {
        ctx.setFillColor(CGColor(red: 0.3, green: 0.22, blue: 0.18, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
    ctx.rotate(by: angle * .pi / 180)
    ctx.translateBy(x: -pw / 2, y: -ph / 2)
    if !clear { ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph)) }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: font, size: size)!, .foregroundColor: NSColor.black]
    for t in texts { (t.s as NSString).draw(at: NSPoint(x: t.x * pw, y: (1 - t.y) * ph - size), withAttributes: attrs) }
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String, type: UTType = .jpeg, orientation: Int? = nil) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, type.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
    if let o = orientation { props[kCGImagePropertyOrientation] = o }
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))
}

func lines(_ items: [String], x: CGFloat = 0.1, top: CGFloat = 0.12, step: CGFloat = 0.07) -> [Text] {
    items.enumerated().map { Text(s: $1, x: x, y: top + CGFloat($0) * step) }
}

/// A simple page with one word to look for.
func wordPage(_ word: String, desk: Bool = true) -> CGImage {
    page(w: 1200, h: 1600, texts: lines(["Notes about \(word)", "remember the \(word) list", "call home today"]),
         size: 64, desk: desk, angle: desk ? 4 : 0)
}

// Page order and plain JPEGs.
save(wordPage("apple"), "1.jpg")
save(wordPage("banana"), "2.jpg")
save(wordPage("cherry"), "10.jpg")
// Uppercase extension, odd names.
save(wordPage("garden"), "upper.JPG")
save(wordPage("window"), "name with spaces \u{e9}t\u{e9} \u{65e5}\u{8a18}.jpg")
// PNG with a see-through background: dark text on nothing.
save(page(w: 1200, h: 1600, texts: lines(["Notes about pencil", "remember the pencil list"]), size: 64, clear: true),
     "clear.png", type: .png)
// The camera stored the photo sideways and set the orientation tag (6 means turn 90 degrees clockwise to view).
let upright = page(w: 1200, h: 1600, texts: lines(["Notes about turtle", "remember the turtle list"]), size: 64)
let sideways = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sideways.translateBy(x: 1600, y: 0); sideways.rotate(by: .pi / 2)
sideways.draw(upright, in: CGRect(x: 0, y: 0, width: 1200, height: 1600))
save(sideways.makeImage()!, "rotated.jpg", orientation: 6)
// Blank paper, tiny and huge images.
save(page(w: 1200, h: 1600, texts: [], size: 64, desk: true), "blank.jpg")
save(page(w: 50, h: 50, texts: [Text(s: "hi", x: 0.1, y: 0.1)], size: 20), "tiny.jpg")
save(page(w: 8000, h: 6000, texts: lines(["Notes about rocket", "remember the rocket list"], top: 0.2, step: 0.1), size: 300),
     "huge.jpg")
// Sources for sips: HEIC and TIFF are made by run_tests.sh.
save(wordPage("castle"), "heic-source.jpg")
save(wordPage("forest"), "tiff-source.jpg")

// A two-page PDF with text drawn as images, like a scan.
let pdfURL = out.appendingPathComponent("scan.pdf") as CFURL
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let pdf = CGContext(pdfURL, mediaBox: &box, nil)!
for word in ["dolphin", "lantern"] {
    pdf.beginPDFPage(nil)
    pdf.draw(wordPage(word, desk: false), in: box)
    pdf.endPDFPage()
}
pdf.closePDF()
// The same PDF locked with a password.
let locked = PDFDocument(url: pdfURL as URL)!
precondition(locked.write(to: out.appendingPathComponent("locked.pdf"),
                          withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"]))

// Two columns, rows lined up across the page, with a title over both. Read row by row this would mix
// the columns, so the order of the output shows whether the columns were found.
let left = ["the morning class covered", "how plants make sugar", "using light and water", "inside the green leaves",
            "this is called photosynthesis", "oxygen leaves the plant", "kitchen herbs need sun"]
let right = ["river water moves slowly", "through the wide valley", "and carries small stones", "down to the open sea",
             "erosion shapes the land", "over thousands of years", "ocean tides come twice a day"]
var two = [Text(s: "Weekly Reading Notes", x: 0.3, y: 0.06)]
two += lines(left, x: 0.06, top: 0.16, step: 0.1) + lines(right, x: 0.53, top: 0.16, step: 0.1)
save(page(w: 2400, h: 3000, texts: two, size: 46, desk: true, angle: 2), "two-columns.jpg")

// One column with a few short notes in the right margin. Must stay row by row.
var margin = lines(["Project meeting on Monday", "the budget is too high", "we need a smaller team", "ask Sam about the dates",
                    "testing starts next week", "the client wants a demo", "write the summary tonight", "book the big room",
                    "order more paper", "send the final report"], x: 0.06, top: 0.08, step: 0.085)
margin += [Text(s: "urgent", x: 0.75, y: 0.165), Text(s: "maybe", x: 0.75, y: 0.42), Text(s: "Friday", x: 0.75, y: 0.675)]
save(page(w: 2400, h: 3000, texts: margin, size: 60, desk: true, angle: -2), "margin-notes.jpg")

// Many margin notes: one beside every other line.
var busy = lines(["Project meeting on Monday", "the budget is too high", "we need a smaller team", "ask Sam about the dates",
                  "testing starts next week", "the client wants a demo", "write the summary tonight", "book the big room",
                  "order more paper", "send the final report", "check the numbers again"], x: 0.06, top: 0.08, step: 0.08)
busy += ["urgent", "maybe", "Friday", "done", "later", "ask Kim"].enumerated()
    .map { Text(s: $1, x: 0.75, y: 0.08 + CGFloat($0) * 0.16) }
save(page(w: 2400, h: 3000, texts: busy, size: 60, desk: true, angle: 2), "margin-busy.jpg")

// A list with indented lines under each item. Must stay one column.
let indent = lines(["Groceries for the week", "fruit", "green apples", "ripe bananas", "dairy", "plain yogurt",
                    "cheddar cheese", "bread", "whole wheat loaf", "bagels"], x: 0.08, top: 0.08, step: 0.085)
    .enumerated().map { i, t in [2, 3, 5, 6, 8, 9].contains(i) ? Text(s: t.s, x: 0.3, y: t.y) : t }
save(page(w: 2400, h: 3000, texts: indent, size: 60, desk: true, angle: 1), "indented.jpg")

// Short labels with a note beside each one (a small table). Must stay row by row so each label keeps its note.
let days = ["Mon", "Tuesday", "Wed", "Thursday", "Fri", "Saturday", "Sun"]
let plans = ["gym and laundry", "dentist at noon", "pay the rent", "dinner with Alex", "movie night", "clean the garage", "rest"]
var table = lines(days, x: 0.08, top: 0.1, step: 0.11)
table += lines(plans, x: 0.5, top: 0.1, step: 0.11)
save(page(w: 2400, h: 3000, texts: table, size: 60, desk: true, angle: 1), "table.jpg")

// A line that wraps onto the next one, a list without bullets, and a line followed by a capitalized one.
// Only the first pair should be joined.
let wrapped = lines(["Plans never say what we should do", "when things go wrong at work", "Shopping", "milk and bread",
                     "fresh eggs", "Call the bank about the new card", "Tuesday morning"], x: 0.06, top: 0.08, step: 0.1)
save(page(w: 1600, h: 2000, texts: wrapped, size: 56, desk: true, angle: 2), "wrapped.jpg")
