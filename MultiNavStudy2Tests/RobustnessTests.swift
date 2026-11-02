// RobustnessTests.swift
// Drives every map the way a participant might: dragging everywhere, tapping,
// double tapping, two-finger double tapping, swiping through the items and
// finishing, with the information items all on and all off, so nothing can
// crash in a session. Also checks that the touch surface is a VoiceOver
// direct-touch area and hands each VoiceOver gesture to the map once, even
// a magic tap made with VoiceOver focus on the top bar.

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import MultiNavStudy2

/// Records what the touch surface reports.
@MainActor
final class GestureRecorder: TactileCanvasDelegate {
    var finishes: [String] = []
    var items: [(forward: Bool, gesture: String)] = []
    var twoFingerDoubleTaps: [String] = []

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {}
    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {}
    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {}
    func canvasTwoFingerDoubleTap(_ canvas: TactileCanvasView, gesture: String) { twoFingerDoubleTaps.append(gesture) }
    func canvasRequestsFinish(_ canvas: TactileCanvasView, gesture: String) { finishes.append(gesture) }
    func canvasRequestsItem(_ canvas: TactileCanvasView, forward: Bool, gesture: String) {
        items.append((forward, gesture))
    }
}

@Suite(.serialized)
@MainActor
struct RobustnessTests {
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    /// Drags across the whole map row by row, then taps and double taps on a grid.
    private func explore(_ controller: any StudyMapController, canvas: TactileCanvasView, area: CGRect) {
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
        controller.canvasTwoFingerDoubleTap(canvas, gesture: "Test")
        for forward in [true, true, false, true, true, true, true, true, true] {
            controller.canvasRequestsItem(canvas, forward: forward, gesture: "Test")
        }
        controller.canvasTwoFingerDoubleTap(canvas, gesture: "Test")
    }

    private func draw(_ scene: any MapScene) {
        let transform = MapTransform(mapSize: scene.mapSize, centered: scene.isCentered, in: screen)
        _ = UIGraphicsImageRenderer(size: screen.size).image { context in
            scene.draw(in: context.cgContext, transform: transform)
        }
    }

    @Test(arguments: StudyContent.maps)
    func everyMapSurvivesAVisit(map: StudyMap) throws {
        let store = SettingsStore.shared
        let saved = store.settings
        defer { store.settings = saved }
        for allOn in [true, false] {
            var settings = saved
            settings.participantID = "TEST"
            for category in InfoCategory.allCases { settings.info[category] = allOn }
            settings.showMap = allOn
            store.settings = settings

            let visit = MapVisit(map: map)
            let controller = try #require(visit.controller, "\(map.id) did not load")
            let canvas = TactileCanvasView(frame: screen)
            canvas.scene = controller
            canvas.delegate = controller
            controller.canvas = canvas
            var closed = false
            visit.onClose = { closed = true }
            visit.appear()
            draw(controller)
            let area = controller.isCentered
                ? CGRect(x: -controller.mapSize.width / 2, y: -controller.mapSize.height / 2,
                         width: controller.mapSize.width, height: controller.mapSize.height)
                : CGRect(origin: .zero, size: controller.mapSize)
            explore(controller, canvas: canvas, area: area)
            controller.canvasRequestsFinish(canvas, gesture: "Test")
            #expect(closed, "the participant's gesture closes the map by default")
            #expect(visit.isFinished)
            visit.disappear()
        }
        StudySession.shared.end(reason: "Test finished")
        Self.removeTestLogs()
    }

    /// The logs these tests write, under the participant ID TEST.
    static func removeTestLogs() {
        let files = (try? FileManager.default.contentsOfDirectory(at: StudyLog.documents, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("TEST_") || file.lastPathComponent.hasPrefix("Session_") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test func gestureCanBeTurnedOff() throws {
        let store = SettingsStore.shared
        let saved = store.settings
        defer { store.settings = saved }
        store.settings.participantCanFinish = false
        store.settings.participantID = "TEST"
        let map = try #require(StudyContent.map(id: "intersection_1"))
        let visit = MapVisit(map: map)
        let controller = try #require(visit.controller)
        var closed = false
        visit.onClose = { closed = true }
        visit.appear()
        controller.onFinishRequest?("Test")
        #expect(!closed)
        visit.finish(by: "Done button")
        #expect(closed, "the researcher's Done always works")
        StudySession.shared.end(reason: "Test finished")
        Self.removeTestLogs()
    }

    @Test func mapIsAVoiceOverDirectTouchArea() {
        let canvas = TactileCanvasView(frame: screen)
        canvas.configureAccessibility(label: "Intersection map")
        #expect(canvas.isAccessibilityElement)
        #expect(canvas.accessibilityTraits.contains(.allowsDirectInteraction))
        #expect(canvas.accessibilityDirectTouchOptions.contains(.silentOnTouch))
        #expect(canvas.accessibilityLabel == "Intersection map")
        #expect(canvas.accessibilityHint == nil)
    }

    /// VoiceOver's own gestures that still mean something on the map. The
    /// items are stepped through with two-finger swipes, which the direct
    /// touch area hands to the map as touches, so a VoiceOver three-finger
    /// scroll up or down does nothing there.
    @Test func voiceOverGesturesReachTheMap() async throws {
        let canvas = TactileCanvasView(frame: screen)
        let recorder = GestureRecorder()
        canvas.delegate = recorder

        #expect(!canvas.accessibilityScroll(.up))
        #expect(!canvas.accessibilityScroll(.down))
        #expect(canvas.accessibilityScroll(.right))
        #expect(!canvas.accessibilityScroll(.left))
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(canvas.accessibilityPerformEscape())
        #expect(canvas.accessibilityPerformMagicTap())

        #expect(recorder.items.isEmpty)
        #expect(recorder.finishes == ["VoiceOver three-finger swipe right", "VoiceOver escape"])
        #expect(recorder.twoFingerDoubleTaps == ["VoiceOver magic tap"])
    }

    /// Two fingers up or down step through the items, three to the right
    /// finish; anything else, or too short a swipe, means nothing.
    @Test func swipesAreReadByFingersAndDirection() {
        let far = TactileCanvasView.swipeDistance + 10
        #expect(TactileCanvasView.swipe(fingers: 2, dx: 5, dy: -far) == .next)
        #expect(TactileCanvasView.swipe(fingers: 2, dx: -5, dy: far) == .previous)
        #expect(TactileCanvasView.swipe(fingers: 2, dx: 0, dy: -30) == nil, "too short")
        #expect(TactileCanvasView.swipe(fingers: 2, dx: far, dy: 0) == nil)
        #expect(TactileCanvasView.swipe(fingers: 2, dx: far, dy: -far) == nil, "diagonal")
        #expect(TactileCanvasView.swipe(fingers: 3, dx: far, dy: 5) == .finish)
        #expect(TactileCanvasView.swipe(fingers: 3, dx: 0, dy: -far) == nil, "three fingers up no longer steps")
        #expect(TactileCanvasView.swipe(fingers: 3, dx: -far, dy: 0) == nil)
        #expect(TactileCanvasView.swipe(fingers: 4, dx: 0, dy: -far) == nil)
    }

    /// A magic tap with VoiceOver focus on the top bar ends at the app
    /// delegate, which hands it to the map on screen. With no map open it is
    /// left to the system.
    @Test func magicTapOffTheMapReachesIt() throws {
        let store = SettingsStore.shared
        let saved = store.settings
        defer { store.settings = saved }
        store.settings.participantID = "TEST"
        let delegate = try #require(UIApplication.shared.delegate as? NSObject)
        #expect(!delegate.accessibilityPerformMagicTap(), "no map open")

        let map = try #require(StudyContent.map(id: "intersection_1"))
        let visit = MapVisit(map: map)
        let controller = try #require(visit.controller)
        let canvas = TactileCanvasView(frame: screen)
        let recorder = GestureRecorder()
        canvas.delegate = recorder
        controller.canvas = canvas
        visit.appear()
        #expect(delegate.accessibilityPerformMagicTap())
        #expect(recorder.twoFingerDoubleTaps == ["VoiceOver magic tap"])
        visit.finish(by: "Done button")
        #expect(!delegate.accessibilityPerformMagicTap(), "the map has closed")
        StudySession.shared.end(reason: "Test finished")
        Self.removeTestLogs()
    }

    /// The swipe recogniser and the raw touch check can both see one swipe,
    /// and VoiceOver can send a two-finger double tap both ways.
    @Test func oneGestureCountsOnce() {
        let canvas = TactileCanvasView(frame: screen)
        let recorder = GestureRecorder()
        canvas.delegate = recorder
        #expect(canvas.accessibilityScroll(.right))
        #expect(canvas.accessibilityPerformEscape())
        #expect(recorder.finishes.count == 1)
        #expect(canvas.accessibilityPerformMagicTap())
        #expect(canvas.accessibilityPerformMagicTap())
        #expect(recorder.twoFingerDoubleTaps.count == 1)
    }
}
