// RobustnessTests.swift
// Drives every map the way a participant might: dragging everywhere, tapping,
// double tapping, moving through every section and back, drawing each map,
// with the main settings all on and all off, so nothing can crash in a
// session. Also checks that the touch surface is a VoiceOver direct-touch
// area and hands each VoiceOver gesture to the map once.

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import MultiNavStudy2

/// Records what the touch surface reports.
@MainActor
final class GestureRecorder: TactileCanvasDelegate {
    var backs: [String] = []
    var sections: [(forward: Bool, gesture: String, voiceOverScroll: Bool)] = []
    var magicTaps = 0
    var sectionAnswer = true

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {}
    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {}
    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {}
    func canvasRequestsBack(_ canvas: TactileCanvasView, gesture: String) { backs.append(gesture) }
    func canvasRequestsSection(_ canvas: TactileCanvasView, forward: Bool, gesture: String,
                               voiceOverScroll: Bool) -> Bool {
        sections.append((forward, gesture, voiceOverScroll))
        return sectionAnswer
    }
    func canvasMagicTap(_ canvas: TactileCanvasView) { magicTaps += 1 }
}

@Suite(.serialized)
@MainActor
struct RobustnessTests {
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    private func config(_ route: RouteInfo, mode: MapMode, allOn: Bool) -> SessionConfig {
        var settings = StudySettings()
        settings.routeID = route.id
        settings.stage = mode == .fullRoute ? .preJourney : .onRoute
        var options = settings[settings.stage]
        options.mapMode = mode
        if !allOn {
            options.turnByTurn = false
            options.distances = false
            options.streetSide = false
            options.intersectionDetails = false
            options.crosswalkDetails = false
            options.intersectionCloseUps = false
            options.landmarks = false
            options.showMap = false
            options.vibration = false
            options.sounds = false
            options.speech = false
        }
        settings[settings.stage] = options
        return SessionConfig(route: route, settings: settings)
    }

    /// Drags across the whole map row by row, then taps and double taps on a grid.
    private func explore(_ controller: any MapController, canvas: TactileCanvasView, area: CGRect) {
        var y = area.minY
        while y <= area.maxY {
            controller.canvas(canvas, touch: .began, mm: CGPoint(x: area.minX, y: y), screen: .zero)
            var x = area.minX
            while x <= area.maxX {
                controller.canvas(canvas, touch: .moved, mm: CGPoint(x: x, y: y), screen: .zero)
                x += 2
            }
            controller.canvas(canvas, touch: .ended, mm: CGPoint(x: area.maxX, y: y), screen: .zero)
            y += 4
        }
        y = area.minY
        while y <= area.maxY {
            var x = area.minX
            while x <= area.maxX {
                let p = CGPoint(x: x, y: y)
                controller.canvas(canvas, touch: .began, mm: p, screen: .zero)
                controller.canvas(canvas, touch: .ended, mm: p, screen: .zero)
                controller.canvas(canvas, singleTapAt: p, screen: .zero)
                controller.canvas(canvas, doubleTapAt: p, screen: .zero)
                x += 6
            }
            y += 6
        }
        controller.canvasMagicTap(canvas)
    }

    private func draw(_ scene: any MapScene) {
        let transform = MapTransform(mapSize: scene.mapSize, centered: scene.isCentered, in: screen)
        _ = UIGraphicsImageRenderer(size: screen.size).image { context in
            scene.draw(in: context.cgContext, transform: transform)
        }
    }

    @Test(arguments: RouteCatalog.routes)
    func routeMapsSurviveASession(route: RouteInfo) throws {
        for mode in MapMode.allCases {
            for allOn in [true, false] {
                let session = RouteSession(config: config(route, mode: mode, allOn: allOn))
                let controller = try #require(session.controller, "Route \(route.number) did not load")
                let canvas = TactileCanvasView(frame: screen)
                canvas.scene = controller
                canvas.delegate = controller
                controller.canvas = canvas
                session.appear()
                var visited = 0
                repeat {
                    visited += 1
                    draw(controller)
                    explore(controller, canvas: canvas, area: CGRect(origin: .zero, size: controller.mapSize))
                } while session.moveSection(forward: true, gesture: "Test")
                if mode == .sections {
                    #expect(visited == route.sections.count)
                    #expect(!session.moveSection(forward: true, gesture: "Test"), "moved past the last section")
                    while session.moveSection(forward: false, gesture: "Test", voiceOverScroll: true) {}
                    #expect(session.currentSection?.index == 1)
                } else {
                    #expect(visited == 1)
                }
                _ = controller.canvasRequestsSection(canvas, forward: true, gesture: "Test", voiceOverScroll: false)
                session.magicTap()
                session.requestLeave(gesture: "Test")
                session.end(reason: "Test finished")
                #expect(!StudyLog.shared.isSessionActive)
            }
        }
    }

    @Test(arguments: RouteCatalog.routes)
    func closeUpsSurviveExploring(route: RouteInfo) throws {
        let directions = try RouteDirections.load(named: route.directions)
        for allOn in [true, false] {
            let config = config(route, mode: .fullRoute, allOn: allOn)
            let composer = DirectionsComposer(directions: directions, config: config)
            for file in route.details {
                let map = try MapLoader.detail(named: file)
                let controller = DetailController(config: config, map: map, composer: composer,
                                                  section: directions.section(withDetail: file))
                let canvas = TactileCanvasView(frame: screen)
                canvas.scene = controller
                canvas.delegate = controller
                controller.canvas = canvas
                controller.screenDidAppear()
                draw(controller)
                let area = CGRect(x: -map.size.width / 2, y: -map.size.height / 2,
                                  width: map.size.width, height: map.size.height)
                explore(controller, canvas: canvas, area: area)
                #expect(!controller.canvasRequestsSection(canvas, forward: true, gesture: "Test", voiceOverScroll: true))
                #expect(!controller.intro.isEmpty)
            }
        }
        FeedbackManager.shared.configure(FeedbackManager.Options())
    }

    /// A locked map keeps the participant on it; the researcher's End still works.
    @Test func lockedMapStaysOpen() throws {
        let route = try #require(RouteCatalog.routes.first)
        var settings = StudySettings()
        settings.routeID = route.id
        settings.participantCanLeave = false
        var left = false
        let session = RouteSession(config: SessionConfig(route: route, settings: settings))
        session.onLeave = { left = true }
        session.appear()
        session.requestLeave(gesture: "Test")
        #expect(!left)
        #expect(StudyLog.shared.isSessionActive)
        session.end(reason: "Test finished")
        #expect(left)
        #expect(!StudyLog.shared.isSessionActive)
    }

    @Test func backGesturesLeaveByDefault() throws {
        let route = try #require(RouteCatalog.routes.first)
        #expect(StudySettings().participantCanLeave)
        var settings = StudySettings()
        settings.routeID = route.id
        var left = false
        let session = RouteSession(config: SessionConfig(route: route, settings: settings))
        session.onLeave = { left = true }
        session.appear()
        session.requestLeave(gesture: "Test")
        #expect(left)
        #expect(!StudyLog.shared.isSessionActive)
    }

    @Test func mapIsAVoiceOverDirectTouchArea() {
        let canvas = TactileCanvasView(frame: screen)
        canvas.configureAccessibility(label: "Route 1, section 1 of 7", hint: "Drag to explore.")
        #expect(canvas.isAccessibilityElement)
        #expect(canvas.accessibilityTraits.contains(.allowsDirectInteraction))
        #expect(canvas.accessibilityDirectTouchOptions.contains(.silentOnTouch))
        #expect(canvas.accessibilityLabel == "Route 1, section 1 of 7")
        #expect(canvas.accessibilityHint == "Drag to explore.")
    }

    @Test func voiceOverGesturesReachTheMap() async throws {
        let canvas = TactileCanvasView(frame: screen)
        let recorder = GestureRecorder()
        canvas.delegate = recorder

        #expect(canvas.accessibilityScroll(.up))
        try await Task.sleep(nanoseconds: 600_000_000)
        recorder.sectionAnswer = false
        #expect(!canvas.accessibilityScroll(.down), "the boundary must reach VoiceOver")
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(canvas.accessibilityScroll(.right))
        #expect(!canvas.accessibilityScroll(.left))
        #expect(canvas.accessibilityPerformEscape())
        #expect(canvas.accessibilityPerformMagicTap())

        let directions = recorder.sections.map { $0.forward }
        let allFromVoiceOver = recorder.sections.allSatisfy { $0.voiceOverScroll }
        #expect(directions == [true, false])
        #expect(allFromVoiceOver)
        #expect(recorder.backs == ["VoiceOver three-finger swipe right", "VoiceOver escape"])
        #expect(recorder.magicTaps == 1)
    }

    /// The swipe recogniser and the raw touch check can both see one swipe.
    @Test func oneSwipeCountsOnce() {
        let canvas = TactileCanvasView(frame: screen)
        let recorder = GestureRecorder()
        canvas.delegate = recorder
        #expect(canvas.accessibilityScroll(.up))
        #expect(canvas.accessibilityScroll(.up))
        #expect(recorder.sections.count == 1)
    }
}
