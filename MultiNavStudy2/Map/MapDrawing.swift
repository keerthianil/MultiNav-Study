// MapDrawing.swift
// Core Graphics helpers shared by both kinds of map.

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

    /// Where each zebra bar starts along a crossing of the given length, and the
    /// gap between neighbouring bars. The span is cut into equal cells with one
    /// bar centred in each: up to `maxCount` cells, but never so many that the
    /// gap drops below `minGap`. A short span, such as one half of a crossing
    /// split by an island, so gets fewer bars instead of bars that run together.
    static func stripeLayout(length: CGFloat, stripeLength: CGFloat, maxCount: Int,
                             minGap: CGFloat) -> (offsets: [CGFloat], gap: CGFloat) {
        guard length > 0, maxCount > 0 else { return ([], 0) }
        let fitting = Int((length / (stripeLength + minGap)).rounded(.down))
        let count = min(maxCount, max(1, fitting))
        let cell = length / CGFloat(count)
        let offsets = (0..<count).map { cell * (CGFloat($0) + 0.5) - stripeLength / 2 }
        return (offsets, max(cell - stripeLength, 0))
    }

    /// Zebra bars across a crossing, each bar parallel to traffic.
    static func crosswalkStripes(from a: CGPoint, to b: CGPoint, stripeLength: CGFloat, stripeWidth: CGFloat,
                                 maxCount: Int, minGap: CGFloat, in context: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 1 else { return }
        let ux = (b.x - a.x) / length
        let uy = (b.y - a.y) / length
        context.setStrokeColor(MapStyle.crosswalkWhite.cgColor)
        context.setLineWidth(stripeWidth)
        context.setLineCap(.butt)
        let layout = stripeLayout(length: length, stripeLength: stripeLength, maxCount: maxCount, minGap: minGap)
        for offset in layout.offsets {
            context.beginPath()
            context.move(to: CGPoint(x: a.x + ux * offset, y: a.y + uy * offset))
            context.addLine(to: CGPoint(x: a.x + ux * (offset + stripeLength), y: a.y + uy * (offset + stripeLength)))
            context.strokePath()
        }
        context.setLineCap(.round)
    }

    /// An unmarked crossing: two thin dashed lines along its edges, where a
    /// marked one has zebra bars.
    static func unmarkedCrossing(from a: CGPoint, to b: CGPoint, offset: CGFloat, lineWidth: CGFloat,
                                 dash: CGFloat, in context: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 1 else { return }
        let nx = -(b.y - a.y) / length
        let ny = (b.x - a.x) / length
        context.saveGState()
        context.setStrokeColor(MapStyle.crosswalkWhite.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)
        context.setLineDash(phase: 0, lengths: [dash, dash * 0.75])
        for side: CGFloat in [-1, 1] {
            context.beginPath()
            context.move(to: CGPoint(x: a.x + nx * offset * side, y: a.y + ny * offset * side))
            context.addLine(to: CGPoint(x: b.x + nx * offset * side, y: b.y + ny * offset * side))
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A label printed on the map, centred on `center`, black with a white
    /// halo so it reads over any colour.
    static func label(_ text: String, at center: CGPoint, size: CGFloat, angle: CGFloat, in context: CGContext) {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let halo = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.white,
            .strokeColor: UIColor.white, .strokeWidth: -16,
        ])
        let ink = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: MapStyle.labelBlack])
        let textSize = ink.size()
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle * .pi / 180)
        let origin = CGPoint(x: -textSize.width / 2, y: -textSize.height / 2)
        UIGraphicsPushContext(context)
        halo.draw(at: origin)
        ink.draw(at: origin)
        UIGraphicsPopContext()
        context.restoreGState()
    }

    /// A dark screen for when the researcher hides the map. Touch still works.
    static func drawHiddenMap(in context: CGContext) {
        let bounds = context.boundingBoxOfClipPath
        context.setFillColor(UIColor.black.cgColor)
        context.fill(bounds)
        let text = NSAttributedString(string: "Map hidden", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor(white: 0.25, alpha: 1),
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
