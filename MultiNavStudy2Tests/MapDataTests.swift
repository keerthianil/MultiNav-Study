// MapDataTests.swift
// Checks the bundled maps load and agree with each other.

import CoreGraphics
import Foundation
import Testing
@testable import MultiNavStudy2

@MainActor
struct MapDataTests {
    @Test func catalogListsFourRoutes() {
        #expect(RouteCatalog.routes.map(\.number) == [1, 2, 3, 4])
    }

    @Test(arguments: RouteCatalog.routes)
    func overviewLoads(route: RouteInfo) throws {
        let map = try MapLoader.overview(named: route.overview)
        #expect(map.route.count >= 2)
        #expect(!map.streets.isEmpty)
        #expect(map.waypointIDs.count == route.details.count)
        for id in map.waypointIDs {
            let intersection = try #require(map.intersections.first { $0.id == id })
            #expect(route.details.contains(intersection.detailFile))
        }
    }

    @Test(arguments: RouteCatalog.routes)
    func overviewFitsItsArea(route: RouteInfo) throws {
        let map = try MapLoader.overview(named: route.overview)
        let area = CGRect(origin: .zero, size: map.size)
        for point in map.route + map.intersections.map(\.position) {
            #expect(area.contains(point))
        }
    }

    @Test(arguments: RouteCatalog.routes.flatMap(\.details))
    func intersectionLoads(file: String) throws {
        let map = try MapLoader.detail(named: file)
        #expect(map.route.count >= 2)
        #expect(!map.roads.isEmpty)
        #expect(!map.sidewalks.isEmpty)
        #expect(map.isRoundabout == (map.ring != nil))
        let half = CGSize(width: map.size.width / 2, height: map.size.height / 2)
        for point in [map.route.first!, map.route.last!] {
            #expect(abs(point.x) <= half.width && abs(point.y) <= half.height, "route end off screen in \(file)")
        }
    }

    @Test func roundaboutHasSplitCrossings() throws {
        let map = try MapLoader.detail(named: "route1_l2_roundabout")
        #expect(map.isRoundabout)
        #expect(map.centralIsland != nil)
        #expect(map.crosswalks.contains { $0.name.hasSuffix("entry lane") })
        #expect(map.crosswalks.contains { $0.name.hasSuffix("exit lane") })
        #expect(map.islands.count >= 4)
    }

    @Test func spokenTextHasNoDashes() throws {
        var texts: [String] = []
        for route in RouteCatalog.routes {
            let overview = try MapLoader.overview(named: route.overview)
            texts += overview.streets.map(\.name) + overview.intersections.map(\.announcement)
                + overview.landmarks.map(\.announcement) + overview.endpoints.map(\.announcement)
            for file in route.details {
                let detail = try MapLoader.detail(named: file)
                texts += [detail.intro] + detail.crosswalks.map(\.name) + detail.sidewalks.map(\.name)
                    + detail.roads.map(\.name) + detail.islands.map(\.name) + detail.endpoints.map(\.announcement)
            }
        }
        for text in texts {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "dash in: \(text)")
            #expect(!text.contains("\u{2192}"), "arrow in: \(text)")
        }
    }

    @Test func shortCrossingsGetFewerStripes() {
        let style = MapStyle.Detail.self
        func count(_ length: CGFloat) -> Int {
            MapDrawing.stripeLayout(length: length, stripeLength: style.crosswalkStripeLength,
                                    maxCount: style.crosswalkStripes, minGap: style.crosswalkStripeMinGap).offsets.count
        }
        #expect(count(11.4) == 3)
        #expect(count(4.2) == 2)
        #expect(count(1.9) == 1)
    }

    /// No zebra bars may run together, as they did on crossings split by an island.
    @Test(arguments: RouteCatalog.routes.flatMap(\.details))
    func crosswalkStripesStayApart(file: String) throws {
        let map = try MapLoader.detail(named: file)
        let style = MapStyle.Detail.self
        for crosswalk in map.crosswalks {
            let span = MapGeometry.distance(crosswalk.paintStart, crosswalk.paintEnd)
            let layout = MapDrawing.stripeLayout(length: span, stripeLength: style.crosswalkStripeLength,
                                                 maxCount: style.crosswalkStripes, minGap: style.crosswalkStripeMinGap)
            #expect(!layout.offsets.isEmpty, "\(crosswalk.id) in \(file) has no stripes")
            if layout.offsets.count > 1 {
                #expect(layout.gap >= style.crosswalkStripeMinGap, "\(crosswalk.id) in \(file) stripes run together")
            }
            #expect(layout.offsets.allSatisfy { $0 >= 0 && $0 + style.crosswalkStripeLength <= span + 0.001 },
                    "\(crosswalk.id) in \(file) stripes leave the road")
        }
    }

    @Test func turnsMergeAndSkipGentleBends() {
        let straight = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 1, y: 20)]
        #expect(MapLoader.routeTurns(straight).isEmpty)
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 10)]
        #expect(MapLoader.routeTurns(corner).count == 1)
    }

    @Test func csvEscapesCommasAndQuotes() {
        #expect(CSVWriter.escape("Fore Street") == "Fore Street")
        #expect(CSVWriter.escape("A, and B") == "\"A, and B\"")
        #expect(CSVWriter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func trialTimeFormat() {
        #expect(StudyLog.trialTime(127.46) == "02:07.4")
        #expect(StudyLog.trialTime(0) == "00:00.0")
    }
}
