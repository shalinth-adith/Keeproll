// Generates screenshot fixtures with real text for the expiry scanner (OCR reads them).
// Usage: swift scripts/make_expired_fixtures.swift <outDir>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "KeeprollTests/Fixtures/Expired")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let width = 1179, height = 2556
let space = CGColorSpaceCreateDeviceRGB()
let formatter = DateFormatter()
formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
let long = DateFormatter(); long.dateStyle = .long

func draw(lines: [String], daysAgo: Double, name: String) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.textMatrix = .identity
    var y = CGFloat(height - 400)
    for line in lines {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.1, alpha: 1)]
        let attributed = CFAttributedStringCreate(nil, line as CFString, attrs as CFDictionary)!
        let ctLine = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 80, y: y)
        CTLineDraw(ctLine, ctx)
        y -= 120
    }
    let image = ctx.makeImage()!
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let date = Date().addingTimeInterval(-daysAgo * 86_400)
    let props: [CFString: Any] = [kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifUserComment: "Screenshot",
        kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date),
    ]]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let flight = long.string(from: Date().addingTimeInterval(-12 * 86_400))
let futureFlight = long.string(from: Date().addingTimeInterval(20 * 86_400))
draw(lines: ["Your verification code is", "482913", "Do not share it with anyone."], daysAgo: 9, name: "expired-otp.png")
draw(lines: ["BOARDING PASS", "Flight 6E 2114", "Gate 24   Seat 14A", "Departure \(flight)", "PNR ZK8Q2L"], daysAgo: 14, name: "expired-boarding.png")
draw(lines: ["Your order is out for delivery", "Tracking ID 7788123456", "Delivery partner: Ravi"], daysAgo: 25, name: "expired-delivery.png")
draw(lines: ["BOARDING PASS", "Flight AI 101", "Gate 12   Seat 3C", "Departure \(futureFlight)"], daysAgo: 3, name: "future-boarding.png")
draw(lines: ["Hey, still on for dinner?", "Yes! See you at 8 :)"], daysAgo: 200, name: "plain-chat.png")
print("Wrote 5 expiry fixtures to \(outDir.path)")
