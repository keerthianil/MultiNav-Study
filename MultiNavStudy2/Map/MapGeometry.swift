// MapGeometry.swift
// Small geometry helpers for hit-testing in millimetre map space.

import CoreGraphics

enum MapGeometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Distance from `p` to the segment a-b, and how far along it (0...1) the nearest point is.
    static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (distance: CGFloat, t: CGFloat) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (distance(p, a), 0) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return (distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy)), t)
    }

    static func polylineDistance(_ p: CGPoint, _ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return points.first.map { distance(p, $0) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 0..<(points.count - 1) {
            best = min(best, segmentDistance(p, points[i], points[i + 1]).distance)
        }
        return best
    }

    /// Distance along the polyline to the point on it nearest `p`.
    static func arcLength(of p: CGPoint, along points: [CGPoint]) -> CGFloat {
        var travelled: CGFloat = 0
        var best = (distance: CGFloat.infinity, arc: CGFloat(0))
        for i in 0..<max(points.count - 1, 0) {
            let a = points[i]
            let b = points[i + 1]
            let length = distance(a, b)
            let hit = segmentDistance(p, a, b)
            if hit.distance < best.distance {
                best = (hit.distance, travelled + hit.t * length)
            }
            travelled += length
        }
        return best.arc
    }

    static func length(of points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return (0..<(points.count - 1)).reduce(0) { $0 + distance(points[$1], points[$1 + 1]) }
    }

    /// Point at a given distance along a polyline.
    static func point(at travelled: CGFloat, along points: [CGPoint]) -> CGPoint? {
        guard var previous = points.first else { return nil }
        var remaining = max(0, travelled)
        for point in points.dropFirst() {
            let length = distance(previous, point)
            if length > 0, remaining <= length {
                let t = remaining / length
                return CGPoint(x: previous.x + (point.x - previous.x) * t, y: previous.y + (point.y - previous.y) * t)
            }
            remaining -= length
            previous = point
        }
        return points.last
    }

    /// Signed turn in degrees at `b` when walking a -> b -> c.
    static func turnAngle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let h1 = atan2(b.y - a.y, b.x - a.x)
        let h2 = atan2(c.y - b.y, c.x - b.x)
        var d = (h2 - h1) * 180 / .pi
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }
}
