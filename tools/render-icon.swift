// Renders the Hisab app icon: a bahi-khata (red-cloth Indian ledger) motif.
// Usage: swift tools/render-icon.swift <out.png> [size]
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: render-icon.swift <out.png> [size]") }
let outPath = args[1]
let size = args.count >= 3 ? Int(args[2])! : 1024
let S = CGFloat(size)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let khataRed = rgb(0xA4243B)
let weaveRed = rgb(0x7E1B2E)
let kagaz = rgb(0xF5EFE6)
let ink = rgb(0x22333B)
let sona = rgb(0xD9A441)

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 1. Red cloth field
ctx.setFillColor(khataRed)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// 2. Subtle diagonal weave
ctx.saveGState()
ctx.setStrokeColor(weaveRed.copy(alpha: 0.18)!)
ctx.setLineWidth(S / 340)
let step = S / 26
var offset: CGFloat = -S
while offset < S * 2 {
    ctx.move(to: CGPoint(x: offset, y: 0))
    ctx.addLine(to: CGPoint(x: offset + S, y: S))
    ctx.move(to: CGPoint(x: offset + S, y: 0))
    ctx.addLine(to: CGPoint(x: offset, y: S))
    offset += step
}
ctx.strokePath()
ctx.restoreGState()

// 3. Cream ledger page with soft shadow
let pageW = S * 0.62, pageH = S * 0.70
let pageX = (S - pageW) / 2, pageY = (S - pageH) / 2
let page = CGPath(roundedRect: CGRect(x: pageX, y: pageY, width: pageW, height: pageH),
                  cornerWidth: S * 0.035, cornerHeight: S * 0.035, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.045,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(page)
ctx.setFillColor(kagaz)
ctx.fillPath()
ctx.restoreGState()

// Clip everything page-bound from here
ctx.saveGState()
ctx.addPath(page)
ctx.clip()

// 4. Gold binding-thread stripe + stitches along page's left edge
let stripeX = pageX + pageW * 0.11
ctx.setStrokeColor(sona)
ctx.setLineWidth(S / 110)
ctx.move(to: CGPoint(x: stripeX, y: pageY))
ctx.addLine(to: CGPoint(x: stripeX, y: pageY + pageH))
ctx.strokePath()
ctx.setLineCap(.round)
ctx.setLineWidth(S / 90)
for frac: CGFloat in [0.22, 0.5, 0.78] {
    let y = pageY + pageH * frac
    ctx.move(to: CGPoint(x: stripeX - S * 0.022, y: y))
    ctx.addLine(to: CGPoint(x: stripeX + S * 0.022, y: y))
    ctx.strokePath()
}

// 5. Ruled ink lines (light) on lower page
let ruleLeft = pageX + pageW * 0.2, ruleRight = pageX + pageW * 0.9
ctx.setStrokeColor(ink.copy(alpha: 0.28)!)
ctx.setLineWidth(S / 170)
for frac: CGFloat in [0.30, 0.175] {
    let y = pageY + pageH * frac
    ctx.move(to: CGPoint(x: ruleLeft, y: y))
    ctx.addLine(to: CGPoint(x: ruleRight, y: y))
    ctx.strokePath()
}
ctx.restoreGState()

// 6. Bold ink rupee glyph, baseline sitting above the rules
let font = NSFont.systemFont(ofSize: S * 0.40, weight: .heavy)
let attr = NSAttributedString(string: "₹", attributes: [
    .font: font, .foregroundColor: NSColor(cgColor: ink)!,
])
let line = CTLineCreateWithAttributedString(attr)
let bounds = CTLineGetImageBounds(line, ctx)
let glyphX = pageX + (pageW - bounds.width) / 2 - bounds.minX + pageW * 0.045  // optical center, nudged right of stripe
let glyphY = pageY + pageH * 0.42
ctx.textPosition = CGPoint(x: glyphX, y: glyphY)
CTLineDraw(line, ctx)

// Write PNG
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: size, height: size)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)x\(size))")
