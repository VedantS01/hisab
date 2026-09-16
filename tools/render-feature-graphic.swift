// Renders the Google Play feature graphic (1024x500): the brand lockup on
// kagaz ledger paper. Keeps all content inside a 10% safe margin.
// Usage: swift tools/render-feature-graphic.swift <out.png>
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: render-feature-graphic.swift <out.png>") }
let outPath = args[1]
let W: CGFloat = 1024
let H: CGFloat = 500

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

// ---- kagaz ledger paper: cream field, faint ruled lines, red margin rule
ctx.setFillColor(kagaz)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.setStrokeColor(sona.copy(alpha: 0.16)!)
ctx.setLineWidth(2)
var y: CGFloat = 62
while y < H {
    ctx.move(to: CGPoint(x: 0, y: y))
    ctx.addLine(to: CGPoint(x: W, y: y))
    y += 62
}
ctx.strokePath()
ctx.setStrokeColor(khataRed.copy(alpha: 0.20)!)
ctx.setLineWidth(3)
ctx.move(to: CGPoint(x: 74, y: 0))
ctx.addLine(to: CGPoint(x: 74, y: H))
ctx.strokePath()

// ---- measure the wordmark first so the whole lockup can be centered
let devFont = NSFont(name: "KohinoorDevanagari-Semibold", size: 190)
    ?? NSFont(name: "DevanagariMT-Bold", size: 190)
    ?? NSFont.systemFont(ofSize: 190, weight: .semibold)
let word = NSAttributedString(string: "हिसाब", attributes: [
    .font: devFont, .foregroundColor: NSColor(cgColor: khataRed)!,
])
let wordLine = CTLineCreateWithAttributedString(word)
let wordWidth = CGFloat(CTLineGetTypographicBounds(wordLine, nil, nil, nil))

let bookH: CGFloat = 300
let bookW = bookH * 0.82
let gap: CGFloat = 64
let total = bookW + gap + wordWidth
let startX = (W - total) / 2
let bookY = (H - bookH) / 2

// ---- Mark: the bahi ledger (same construction as render-logo.swift)
ctx.saveGState()
ctx.translateBy(x: startX + bookW / 2, y: bookY + bookH / 2)
ctx.rotate(by: -0.03)
ctx.translateBy(x: -bookW / 2, y: -bookH / 2)

let pages = CGPath(roundedRect: CGRect(x: bookW * 0.04, y: bookH * 0.02,
                                       width: bookW, height: bookH * 0.96),
                   cornerWidth: bookH * 0.05, cornerHeight: bookH * 0.05, transform: nil)
ctx.addPath(pages)
ctx.setFillColor(rgb(0xFFFCF5))
ctx.fillPath()
ctx.addPath(pages)
ctx.setStrokeColor(deepRed.copy(alpha: 0.25)!)
ctx.setLineWidth(bookH / 90)
ctx.strokePath()

let cover = CGPath(roundedRect: CGRect(x: 0, y: 0, width: bookW, height: bookH),
                   cornerWidth: bookH * 0.07, cornerHeight: bookH * 0.07, transform: nil)
ctx.addPath(cover)
ctx.setFillColor(khataRed)
ctx.fillPath()

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

// ---- Wordmark on its gold ledger rule, tagline beneath
let textX = startX + bookW + gap
let baselineY = H * 0.46
ctx.textPosition = CGPoint(x: textX, y: baselineY)
CTLineDraw(wordLine, ctx)

ctx.setStrokeColor(sona)
ctx.setLineWidth(10)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: textX, y: baselineY - 40))
ctx.addLine(to: CGPoint(x: textX + wordWidth, y: baselineY - 40))
ctx.strokePath()

let latinFont = NSFont.systemFont(ofSize: 42, weight: .semibold)
let latin = NSAttributedString(string: "UPI Statement Ledger", attributes: [
    .font: latinFont, .foregroundColor: NSColor(cgColor: ink)!,
    .kern: 2.5,
])
let latinLine = CTLineCreateWithAttributedString(latin)
let latinWidth = CGFloat(CTLineGetTypographicBounds(latinLine, nil, nil, nil))
ctx.textPosition = CGPoint(x: textX + (wordWidth - latinWidth) / 2, y: baselineY - 105)
CTLineDraw(latinLine, ctx)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(Int(W))x\(Int(H))")
