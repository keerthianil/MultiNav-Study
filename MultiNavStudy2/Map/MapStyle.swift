// MapStyle.swift
// Colours, physical sizes and touch radii for both kinds of map.
// Every size is in millimetres on the glass, so a road feels the same width
// on every phone. Points come from the MultiNav PhysicalDimensions table.

import UIKit

enum MapStyle {
    static let background = UIColor.white
    static let roadBlue = UIColor(rgb: 0x023E8A)
    static let intersectionRed = UIColor(rgb: 0xC1121F)
    static let routeCyan = UIColor(rgb: 0x48CAE4)
    static let endpointYellow = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
    static let sidewalkGray = UIColor(rgb: 0x9E9E9E)
    static let medianGreen = UIColor(rgb: 0x52B788)
    static let crosswalkWhite = UIColor.white
    static let crosswalkEndPink = UIColor.systemPink
    static let turnOrange = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)
    static let outlineWhite = UIColor.white
    static let labelBlack = UIColor.black

    /// Route overviews.
    enum Overview {
        static let roadWidth: CGFloat = 4.0
        static let routeWidth: CGFloat = 3.5
        static let intersectionSide: CGFloat = 6.0
        static let intersectionBorder: CGFloat = 0.5
        static let endpointDiameter: CGFloat = 6.0
        static let endpointBorder: CGFloat = 0.4
    }

    /// Intersection maps.
    enum Intersection {
        static let sidewalkWidth: CGFloat = 4.0
        /// As wide as the sidewalk it follows, so it covers it.
        static let routeWidth: CGFloat = 4.0
        static let routeOutline: CGFloat = 0.3
        static let crosswalkStripeWidth: CGFloat = 2.8
        static let crosswalkStripeLength: CGFloat = 1.0
        /// Most zebra bars on one crossing; a short span drops bars rather than
        /// close the gap between them below the minimum.
        static let crosswalkStripes = 3
        static let crosswalkStripeMinGap: CGFloat = 1.0
        /// An unmarked crossing: two thin dashed lines along its edges.
        static let unmarkedLineWidth: CGFloat = 0.35
        static let unmarkedLineOffset: CGFloat = 1.4
        static let crosswalkEndDiameter: CGFloat = 5.0
        static let dotBorder: CGFloat = 0.4
        static let turnDiameter: CGFloat = 6.0
        static let endpointDiameter: CGFloat = 6.0
        static let centerMarkDiameter: CGFloat = 2.0
    }

    /// How close a fingertip must be, in mm, to count as touching.
    enum Hit {
        static let endpoint: CGFloat = 4.0
        static let intersection: CGFloat = 3.65
        static let route: CGFloat = 3.65
        static let overviewRoad: CGFloat = 2.0
        static let turn: CGFloat = 3.2
        static let crosswalkEnd: CGFloat = 2.7
        static let crosswalk: CGFloat = 4.0
        static let sidewalk: CGFloat = 2.3
        static let medianSlack: CGFloat = 1.2
        /// Extra distance an element keeps the finger once it has it, so a
        /// finger resting on an edge does not flicker between two elements.
        static let hysteresis: CGFloat = 0.8
    }

    /// Space kept clear around the drawing, in points.
    static let contentPadding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(rgb & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}
