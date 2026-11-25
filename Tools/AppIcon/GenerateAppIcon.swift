import AppKit

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: cs, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
}

let amber = color(0xE8B04B)
let amberHot = color(0xF7CE7A)
let ink = color(0x171A21)
let ivory = color(0xEDE6D6)

// MARK: - 背景

ctx.setFillColor(color(0x0F1117))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

ctx.drawRadialGradient(gradient([color(0xE8B04B, 0.22), color(0xE8B04B, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 500), startRadius: 30,
                       endCenter: CGPoint(x: 512, y: 500), endRadius: 540,
                       options: [.drawsAfterEndLocation])

// MARK: - 机身轮廓（右上角经典大圆弧切口）

let bodyW: CGFloat = 478
let bodyH: CGFloat = 686
let body = CGRect(x: 512 - bodyW / 2, y: 158, width: bodyW, height: bodyH)

let shell = CGMutablePath()
shell.move(to: CGPoint(x: body.minX + 30, y: body.minY))
shell.addLine(to: CGPoint(x: body.maxX - 104, y: body.minY))
shell.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + 104),
                   control: CGPoint(x: body.maxX, y: body.minY))
shell.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 112))
shell.addQuadCurve(to: CGPoint(x: body.maxX - 112, y: body.maxY),
                   control: CGPoint(x: body.maxX, y: body.maxY))
shell.addLine(to: CGPoint(x: body.minX + 34, y: body.maxY))
shell.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - 34),
                   control: CGPoint(x: body.minX, y: body.maxY))
shell.addLine(to: CGPoint(x: body.minX, y: body.minY + 30))
shell.addQuadCurve(to: CGPoint(x: body.minX + 30, y: body.minY),
                   control: CGPoint(x: body.minX, y: body.minY))
shell.closeSubpath()

// 落地投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: color(0x000000, 0.6))
ctx.setFillColor(color(0x000000, 0.9))
ctx.addPath(shell)
ctx.fillPath()
ctx.restoreGState()

// 外壳渐变
ctx.saveGState()
ctx.addPath(shell)
ctx.clip()
ctx.drawLinearGradient(gradient([color(0xF6F0E2), color(0xDAD0BA)], [0, 1]),
                       start: CGPoint(x: 0, y: body.maxY),
                       end: CGPoint(x: 0, y: body.minY),
                       options: [])
ctx.restoreGState()

// 右上弧口的内阴影，强化厚度
ctx.saveGState()
ctx.addPath(shell)
ctx.clip()
ctx.drawRadialGradient(gradient([color(0xB8AB92, 0.55), color(0xB8AB92, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: body.maxX, y: body.maxY), startRadius: 40,
                       endCenter: CGPoint(x: body.maxX, y: body.maxY), endRadius: 300,
                       options: [])
ctx.restoreGState()

// MARK: - 屏幕

let bezel = CGRect(x: body.minX + 52, y: body.maxY - 306, width: body.width - 104, height: 236)
ctx.setFillColor(color(0x2A2D36))
ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.fillPath()

// 屏幕边框内圈
ctx.setStrokeColor(color(0x0A0C11))
ctx.setLineWidth(6)
ctx.addPath(CGPath(roundedRect: bezel.insetBy(dx: 3, dy: 3),
                   cornerWidth: 23, cornerHeight: 23, transform: nil))
ctx.strokePath()

// 发光屏幕
let screen = bezel.insetBy(dx: 22, dy: 20)
let screenPath = CGPath(roundedRect: screen, cornerWidth: 10, cornerHeight: 10, transform: nil)
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
ctx.drawLinearGradient(gradient([color(0x3A2A0D), color(0x8A5F14)], [0, 1]),
                       start: CGPoint(x: 0, y: screen.maxY),
                       end: CGPoint(x: 0, y: screen.minY),
                       options: [])
// 屏幕暖光
ctx.drawRadialGradient(gradient([color(0xF7CE7A, 0.5), color(0xF7CE7A, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: screen.midX, y: screen.midY),
                       startRadius: 0,
                       endCenter: CGPoint(x: screen.midX, y: screen.midY), endRadius: 250,
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 像素心形：八位机时代的通用符号
let heart: [[Int]] = [
    [0, 1, 0, 1, 0],
    [1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1],
    [0, 1, 1, 1, 0],
    [0, 0, 1, 0, 0],
]
let px: CGFloat = 25
let gapPx: CGFloat = 3
let gridW = CGFloat(5) * px + 4 * gapPx
let gridH = CGFloat(5) * px + 4 * gapPx
let originX = screen.midX - gridW / 2
let originY = screen.midY - gridH / 2
for (row, line) in heart.enumerated() {
    for (col, on) in line.enumerated() where on == 1 {
        let r = CGRect(x: originX + CGFloat(col) * (px + gapPx),
                       y: originY + CGFloat(4 - row) * (px + gapPx),
                       width: px, height: px)
        ctx.setFillColor(color(0xF7CE7A, 0.95))
        ctx.fill(r)
    }
}
// 扫描线
ctx.setFillColor(color(0x0A0C11, 0.13))
var sy = screen.minY
while sy < screen.maxY {
    ctx.fill(CGRect(x: screen.minX, y: sy, width: screen.width, height: 3))
    sy += 9
}
ctx.restoreGState()

// 屏幕外发光
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: color(0xE8B04B, 0.75))
ctx.setFillColor(color(0xE8B04B, 0.0))
ctx.addPath(screenPath)
ctx.fillPath()
ctx.restoreGState()

// 屏幕下方品牌线
ctx.setFillColor(color(0x9C8F76, 0.85))
ctx.addPath(CGPath(roundedRect: CGRect(x: bezel.minX + 40, y: bezel.minY - 26,
                                       width: 120, height: 9),
                   cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
ctx.fillPath()

// MARK: - 十字键

let dpadCenter = CGPoint(x: body.minX + 150, y: body.minY + 224)
let arm: CGFloat = 40
let thick: CGFloat = 46
ctx.setFillColor(ink)
let vBar = CGRect(x: dpadCenter.x - thick / 2, y: dpadCenter.y - arm - thick / 2,
                  width: thick, height: (arm + thick / 2) * 2)
let hBar = CGRect(x: dpadCenter.x - arm - thick / 2, y: dpadCenter.y - thick / 2,
                  width: (arm + thick / 2) * 2, height: thick)
for r in [vBar, hBar] {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
}
// 十字中心高光
ctx.setFillColor(color(0x3A3F4C, 0.9))
ctx.addPath(CGPath(roundedRect: CGRect(x: dpadCenter.x - 11, y: dpadCenter.y - 11,
                                       width: 22, height: 22),
                   cornerWidth: 5, cornerHeight: 5, transform: nil))
ctx.fillPath()

// MARK: - A / B 按钮

let btnR: CGFloat = 34
for (cx, cy) in [(body.maxX - 190, body.minY + 250), (body.maxX - 108, body.minY + 176)] {
    let rect = CGRect(x: cx - btnR, y: cy - btnR, width: btnR * 2, height: btnR * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: color(0x000000, 0.35))
    ctx.setFillColor(color(0xB5563C))
    ctx.fillEllipse(in: rect)
    ctx.restoreGState()
    ctx.setFillColor(color(0x7C3423))
    ctx.fillEllipse(in: rect.insetBy(dx: 7, dy: 7))
}

// MARK: - 扬声器格栅（斜向槽）

for i in 0..<6 {
    let cx = body.maxX - 132 + CGFloat(i) * 15
    let cy = body.minY + 84
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -32 * .pi / 180)
    ctx.setFillColor(color(0xB3A78E, 0.95))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -4, y: -27, width: 8, height: 54),
                       cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - 输出

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(S)x\(S)")
