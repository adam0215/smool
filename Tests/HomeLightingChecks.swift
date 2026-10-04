@testable import SmoolChecksSupport
import SwiftUI

@main
struct HomeLightingChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let cardBounds = CGRect(x: 0, y: 0, width: 64, height: 104)

        for leading in [true, false] {
            for inset in [0.0, 1.0] {
                let path = HomeCardShape(edge: leading ? .leading : .trailing).inset(by: inset).path(in: cardBounds)
                let radius = NotchLayout.bottomRadius - NotchLayout.contentInset - inset
                let center = CGPoint(x: leading ? 56 : 8, y: 48)

                for degrees in stride(from: 95.0, through: 175, by: 5) {
                    let angle = degrees * .pi / 180
                    let direction = leading ? 1.0 : -1.0
                    let inside = CGPoint(x: center.x + direction * cos(angle) * (radius - 0.25),
                                         y: center.y + sin(angle) * (radius - 0.25))
                    let outside = CGPoint(x: center.x + direction * cos(angle) * (radius + 0.25),
                                          y: center.y + sin(angle) * (radius + 0.25))
                    precondition(path.cgPath.contains(inside), "The inner arc must retain the outer panel's center.")
                    precondition(!path.cgPath.contains(outside), "The outside edge must stay exactly eight points from the panel.")
                }
            }
        }

        let applets = [
            AppletDestination(id: AppletID(rawValue: "spotify"), title: "Spotify", icon: .symbol("music.note"), tint: .green),
            AppletDestination(id: AppletID(rawValue: "codex"), title: "Codex", icon: .symbol("terminal"), tint: .purple)
        ]
        for (name, card) in [("neutral", HomeCard.clock), ("spotify", .applet(applets[0].id)), ("codex", .applet(applets[1].id))] {
            let glow = card.glow(applets: applets)
            let view = BottomGlow(color: glow.color, horizontalPosition: glow.horizontalPosition, darkHeight: 48)
                .frame(width: 480, height: 152)
                .background(.black)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
            for x in 0..<480 {
                for y in 0..<48 {
                    let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.005,
                                 "Light leaked into the black band in \(name).")
                }
            }
            let left = bitmap.colorAt(x: 120, y: 148)!.usingColorSpace(.deviceRGB)!
            let right = bitmap.colorAt(x: 360, y: 148)!.usingColorSpace(.deviceRGB)!
            if name == "spotify" {
                precondition(left.greenComponent > left.blueComponent && left.greenComponent > right.greenComponent)
            } else if name == "codex" {
                precondition(right.blueComponent > right.greenComponent && right.blueComponent > left.blueComponent)
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("glow-\(name).png"))
        }
        print("Passed: concentric corners, stroke insets, black band, moving glow, and app colors.")
    }
}
