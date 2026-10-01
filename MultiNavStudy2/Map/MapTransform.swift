// MapTransform.swift
// Maps millimetre map coordinates to points on screen and back.
// Uses the MultiNav PhysicalDimensions table so 1 mm is 1 mm on every
// iPhone; the map only shrinks if the screen is smaller than the map.

import CoreGraphics
import TactileMapCore
import UIKit

struct MapTransform {
    /// Screen position of map coordinate (0, 0).
    var origin: CGPoint = .zero
    var pointsPerMM: CGFloat = 1

    /// - Parameters:
    ///   - mapSize: the map's reference area in mm.
    ///   - centered: true when map (0, 0) is the middle of the area (intersection
    ///     views); false when it is the top-left corner (overview maps).
    ///   - rect: the screen area available for drawing.
    init(mapSize: CGSize, centered: Bool, in rect: CGRect) {
        let fullScale = PhysicalDimensions.mmToPoints(1)
        guard mapSize.width > 0, mapSize.height > 0, rect.width > 0, rect.height > 0 else {
            pointsPerMM = fullScale
            return
        }
        let fit = min(1, rect.width / (mapSize.width * fullScale), rect.height / (mapSize.height * fullScale))
        pointsPerMM = fullScale * fit
        if centered {
            origin = CGPoint(x: rect.midX, y: rect.midY)
        } else {
            origin = CGPoint(x: rect.midX - mapSize.width * pointsPerMM / 2,
                             y: rect.midY - mapSize.height * pointsPerMM / 2)
        }
    }

    init() {}

    func point(_ mm: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + mm.x * pointsPerMM, y: origin.y + mm.y * pointsPerMM)
    }

    func mm(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / pointsPerMM, y: (point.y - origin.y) / pointsPerMM)
    }

    func length(_ mm: CGFloat) -> CGFloat {
        mm * pointsPerMM
    }
}
