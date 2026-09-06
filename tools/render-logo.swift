// Renders the Hisab brand logo: bahi-khata book mark + Devanagari wordmark on a
// gold ledger rule, latin letterspaced beneath. Transparent background.
// Usage: swift tools/render-logo.swift <out.png> [width]
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: render-logo.swift <out.png> [width]") }
let outPath = args[1]
let W = CGFloat(args.count >= 3 ? Int(args[2])! : 1600)
let H = W * 0.34

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let khataRed = rgb(0xA4243B)
let deepRed = rgb(0x7E1B2E)
let kagaz = rgb(0xF5EFE6)
let ink = rgb(0x22333B)
let sona = rgb(0xD9A441)

let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// ---- Mark: a closed bahi ledger, slightly tilted, gold thread wrap
let bookH = H * 0.72
let bookW = bookH * 0.82
let bookX = H * 0.10
let bookY = (H - bookH) / 2
ctx.saveGState()
ctx.translateBy(x: bookX + bookW / 2, y: bookY + bookH / 2)
ctx.rotate(by: -0.03)
ctx.translateBy(x: -bookW / 2, y: -bookH / 2)

// kagaz page edges peeking just past the cover's right edge
let pages = CGPath(roundedRect: CGRect(x: bookW * 0.04, y: bookH * 0.02,
                                       width: bookW, height: bookH * 0.96),
                   cornerWidth: bookH * 0.05, cornerHeight: bookH * 0.05, transform: nil)
ctx.addPath(pages)
ctx.setFillColor(kagaz)
ctx.fillPath()
ctx.addPath(pages)
ctx.setStrokeColor(deepRed.copy(alpha: 0.25)!)
ctx.setLineWidth(bookH / 90)
ctx.strokePath()

// red cover
let cover = CGPath(roundedRect: CGRect(x: 0, y: 0, width: bookW, height: bookH),
                   cornerWidth: bookH * 0.07, cornerHeight: bookH * 0.07, transform: nil)
ctx.addPath(cover)
ctx.setFillColor(khataRed)
ctx.fillPath()

// subtle cloth weave on cover
ctx.saveGState()
ctx.addPath(cover)
ctx.clip()
ctx.setStrokeColor(deepRed.copy(alpha: 0.35)!)
ctx.setLineWidth(bookH / 160)
var offset: CGFloat = -bookH
let step = bookH / 11
while offset < bookW + bookH {
    ctx.move(to: CGPoint(x: offset, y: 0))
    ctx.addLine(to: CGPoint(x: offset + bookH, y: bookH))
    offset += step
}
ctx.strokePath()
ctx.restoreGState()

// gold thread: vertical wrap + knot dashes
ctx.setStrokeColor(sona)
ctx.setLineWidth(bookH / 26)
ctx.setLineCap(.round)
let threadX = bookW * 0.30
ctx.move(to: CGPoint(x: threadX, y: bookH * 0.02))
ctx.addLine(to: CGPoint(x: threadX, y: bookH * 0.98))
ctx.strokePath()
ctx.setLineWidth(bookH / 34)
for frac: CGFloat in [0.30, 0.70] {
    ctx.move(to: CGPoint(x: threadX - bookW * 0.09, y: bookH * frac))
    ctx.addLine(to: CGPoint(x: threadX + bookW * 0.09, y: bookH * frac))
    ctx.strokePath()
}
// tiny ₹ embossed on cover, right of thread
let coverFont = NSFont.systemFont(ofSize: bookH * 0.34, weight: .heavy)
let coverRupee = NSAttributedString(string: "₹", attributes: [
    .font: coverFont, .foregroundColor: NSColor(cgColor: kagaz)!,
])
let coverLine = CTLineCreateWithAttributedString(coverRupee)
let cb = CTLineGetImageBounds(coverLine, ctx)
ctx.textPosition = CGPoint(x: threadX + (bookW - threadX - cb.width) / 2 - cb.minX,
                           y: bookH * 0.36)
CTLineDraw(coverLine, ctx)
ctx.restoreGState()

// ---- Wordmark: हिसाब in khata red (typographic bounds, not image bounds —
// Devanagari matras make image bounds unreliable for layout)
let devFont = NSFont(name: "KohinoorDevanagari-Semibold", size: H * 0.44)
    ?? NSFont(name: "DevanagariMT-Bold", size: H * 0.44)
    ?? NSFont.systemFont(ofSize: H * 0.44, weight: .semibold)
let word = NSAttributedString(string: "हिसाब", attributes: [
    .font: devFont, .foregroundColor: NSColor(cgColor: khataRed)!,
])
let wordLine = CTLineCreateWithAttributedString(word)
let wordWidth = CGFloat(CTLineGetTypographicBounds(wordLine, nil, nil, nil))
let textX = bookX + bookW + H * 0.34
let baselineY = H * 0.42
ctx.textPosition = CGPoint(x: textX, y: baselineY)
CTLineDraw(wordLine, ctx)

// gold ledger rule the wordmark sits on
ctx.setStrokeColor(sona)
ctx.setLineWidth(H / 44)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: textX, y: baselineY - H * 0.085))
ctx.addLine(to: CGPoint(x: textX + wordWidth, y: baselineY - H * 0.085))
ctx.strokePath()

// letterspaced latin beneath, ink, centered under the wordmark
let latinFont = NSFont.systemFont(ofSize: H * 0.13, weight: .semibold)
let latin = NSAttributedString(string: "H I S A B", attributes: [
    .font: latinFont, .foregroundColor: NSColor(cgColor: ink)!,
    .kern: H * 0.055,
])
let latinLine = CTLineCreateWithAttributedString(latin)
let latinWidth = CGFloat(CTLineGetTypographicBounds(latinLine, nil, nil, nil))
ctx.textPosition = CGPoint(x: textX + (wordWidth - latinWidth) / 2, y: H * 0.15)
CTLineDraw(latinLine, ctx)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(Int(W))x\(Int(H))")
