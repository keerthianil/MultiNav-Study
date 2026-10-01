// MapDrawing.swift
// Core Graphics helpers shared by both map levels.

import UIKit

enum MapDrawing {
    static func stroke(_ points: [CGPoint], width: CGFloat, color: UIColor, in context: CGContext, _ t: MapTransform) {
        guard points.count > 1 else { return }
        context.beginPath()
        context.move(to: t.point(points[0]))
        for point in points.dropFirst() {
            context.addLine(to: t.point(point))
        }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(t.length(width))
        context.strokePath()
    }

    static func dot(at center: CGPoint, diameter: CGFloat, border: CGFloat, color: UIColor, in context: CGContext) {
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(MapStyle.outlineWhite.cgColor)
        context.setLineWidth(border)
        context.strokeEllipse(in: rect.insetBy(dx: border / 2, dy: border / 2))
    }

    /// Three evenly spaced zebra bars across a crossing, each bar parallel to traffic.
    static func crosswalkStripes(from a: CGPoint, to b: CGPoint, stripeLength: CGFloat, stripeWidth: CGFloat,
                                 count: Int, in context: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 1, count > 0 else { return }
        let ux = (b.x - a.x) / length
        let uy = (b.y - a.y) / length
        let gap = max((length - CGFloat(count) * stripeLength) / CGFloat(count + 1), 0)
        context.setStrokeColor(MapStyle.crosswalkWhite.cgColor)
        context.setLineWidth(stripeWidth)
        context.setLineCap(.butt)
        var offset = gap
        for _ in 0..<count {
            context.beginPath()
            context.move(to: CGPoint(x: a.x + ux * offset, y: a.y + uy * offset))
            context.addLine(to: CGPoint(x: a.x + ux * (offset + stripeLength), y: a.y + uy * (offset + stripeLength)))
            context.strokePath()
            offset += stripeLength + gap
        }
        context.setLineCap(.round)
    }

    /// White label inside a landmark box, shrunk to fit.
    static func drawTag(_ tag: String, in rect: CGRect) {
        guard !tag.isEmpty else { return }
        var size = rect.height * 0.7
        var attributes: [NSAttributedString.Key: Any] = [:]
        var text = NSAttributedString(string: tag)
        repeat {
            attributes = [.font: UIFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: UIColor.white]
            text = NSAttributedString(string: tag, attributes: attributes)
            size -= 0.5
        } while text.size().width > rect.width && size > 4
        let textSize = text.size()
        text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }
}
