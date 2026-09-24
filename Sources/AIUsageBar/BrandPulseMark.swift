import AppKit
import SwiftUI

private enum BrandPulseGeometry {
    private static let compactScale: CGFloat = 1.22

    static func strokes(in bounds: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let compactX = 50 + (x - 50) * compactScale
            let compactY = 50 + (y - 50) * compactScale
            return CGPoint(
                x: bounds.minX + bounds.width * compactX / 100,
                y: bounds.minY + bounds.height * compactY / 100
            )
        }

        let path = CGMutablePath()
        path.move(to: point(37, 52))
        path.addCurve(to: point(68, 34), control1: point(52, 49), control2: point(64, 42))
        path.move(to: point(23, 69))
        path.addCurve(to: point(73, 42), control1: point(46, 66), control2: point(65, 58))
        path.move(to: point(36, 82))
        path.addCurve(to: point(78, 43), control1: point(61, 80), control2: point(76, 63))
        return path
    }

    static func dot(in bounds: CGRect) -> CGPath {
        let diameter = min(bounds.width, bounds.height) * 0.14 * compactScale
        let center = CGPoint(
            x: bounds.minX + bounds.width * (0.5 + (0.79 - 0.5) * compactScale),
            y: bounds.minY + bounds.height * (0.5 + (0.24 - 0.5) * compactScale)
        )
        return CGPath(ellipseIn: CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        ), transform: nil)
    }

    static func strokeWidth(in bounds: CGRect) -> CGFloat {
        min(bounds.width, bounds.height) * 0.075 * compactScale
    }
}

struct BrandPulseMark: View {
    var monochrome = false

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let strokeShading: GraphicsContext.Shading = monochrome
                ? .color(.primary)
                : .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.20, green: 0.45, blue: 1),
                        Color(red: 0.43, green: 0.91, blue: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: size.height),
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            context.stroke(
                Path(BrandPulseGeometry.strokes(in: bounds)),
                with: strokeShading,
                style: StrokeStyle(
                    lineWidth: BrandPulseGeometry.strokeWidth(in: bounds),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.fill(
                Path(BrandPulseGeometry.dot(in: bounds)),
                with: .color(monochrome ? .primary : Color(red: 0.72, green: 0.97, blue: 1))
            )
        }
        .accessibilityHidden(true)
    }
}

enum BrandPulseStatusImage {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(BrandPulseGeometry.strokeWidth(in: bounds))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(BrandPulseGeometry.strokes(in: bounds))
            context.strokePath()
            context.addPath(BrandPulseGeometry.dot(in: bounds))
            context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
