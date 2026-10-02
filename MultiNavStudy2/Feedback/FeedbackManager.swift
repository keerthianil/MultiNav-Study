// FeedbackManager.swift
// The one place map feedback is started and stopped.
//
// Feedback is a single mode at a time. Setting a new mode stops everything
// the old one started (haptic loop, ding timer, click timer) before the new
// one begins, so moving between elements never leaves a stray vibration or
// sound running. Setting the mode that is already playing does nothing.

import UIKit

@MainActor
final class FeedbackManager {
    static let shared = FeedbackManager()

    enum Mode: Equatable {
        case none
        /// Streets, roundabout roadway and junction centre: steady heavy buzz.
        case road
        /// Sidewalks: softer steady buzz.
        case sidewalk
        /// Overview intersections: slow pulse and a ding every 0.4 s.
        case intersection
        /// Landmarks and route start or end: fast pulse.
        case landmark
        /// Route line: rhythmic pulse.
        case route
        /// Crosswalk: click every 0.17 s, with the road buzz when over a road.
        case crosswalk(overRoad: Bool)
        /// Route along a crosswalk: route pulse and crosswalk clicks.
        case routeOverCrosswalk
        /// Route turn dot: ding and a tap every 0.4 s.
        case turn
        /// Crosswalk end dot: one ding, nothing else.
        case crosswalkEnd
        /// Refuge and splitter islands: two soft taps, repeating.
        case island
    }

    private(set) var mode: Mode = .none
    private let haptics = HapticService()
    private let audio = AudioService()
    private let speech = SpeechService()
    private var dingTimer: Timer?
    private var clickTimer: Timer?
    private var lastSpoken: (text: String, time: TimeInterval) = ("", 0)
    private var voiceOverObserver: NSObjectProtocol?

    private init() {
        haptics.onError = { message in
            Task { @MainActor in StudyLog.shared.error(message) }
        }
        audio.onError = { message in
            Task { @MainActor in StudyLog.shared.error(message) }
        }
        voiceOverObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let running = UIAccessibility.isVoiceOverRunning
                StudyLog.shared.event(.voiceOver, running ? "VoiceOver on" : "VoiceOver off")
                FeedbackManager.shared.stopAll()
                FeedbackManager.shared.haptics.restart()
            }
        }
    }

    /// Creates the engines ahead of the first touch.
    func prepare() {
        audio.resume()
        haptics.restart()
    }

    func set(_ newMode: Mode) {
        guard newMode != mode else { return }
        stopCurrentMode()
        mode = newMode
        switch newMode {
        case .none:
            break
        case .road:
            haptics.play(.road)
        case .sidewalk:
            haptics.play(.sidewalk)
        case .intersection:
            haptics.play(.intersection)
            audio.ding()
            dingTimer = repeating(0.4) { $0.audio.ding() }
        case .landmark:
            haptics.play(.landmark)
        case .route:
            haptics.play(.route)
        case .crosswalk(let overRoad):
            if overRoad { haptics.play(.road) }
            startClicks()
        case .routeOverCrosswalk:
            haptics.play(.route)
            startClicks()
        case .turn:
            audio.ding()
            haptics.turnTap()
            dingTimer = repeating(0.4) {
                $0.audio.ding()
                $0.haptics.turnTap()
            }
        case .crosswalkEnd:
            audio.ding()
        case .island:
            haptics.play(.island)
        }
    }

    /// Stops all vibration and sound. Speech already under way is left to finish.
    func stopAll() {
        stopCurrentMode()
        mode = .none
    }

    /// Stops everything including speech, for leaving a screen.
    func silence() {
        stopAll()
        speech.stop()
    }

    /// Speaks at once, cutting off anything still being said. The same words
    /// asked for again within half a second (the two taps of a double tap)
    /// are not repeated.
    func speak(_ text: String) {
        let now = CACurrentMediaTime()
        if text == lastSpoken.text, now - lastSpoken.time < 0.5 { return }
        lastSpoken = (text, now)
        speech.speak(text)
        StudyLog.shared.event(.speech, text)
    }

    /// One sharp tap, for a single tap on the map.
    func pulse() {
        haptics.tap()
    }

    /// One turn ding with its tap, for a single tap on a turn dot.
    func turnDing() {
        audio.ding()
        haptics.turnTap()
    }

    /// Confirms a back gesture.
    func backTap() {
        haptics.turnTap()
    }

    func handleBackground() {
        silence()
        haptics.suspend()
    }

    func handleForeground() {
        audio.resume()
        haptics.restart()
    }

    private func stopCurrentMode() {
        dingTimer?.invalidate()
        dingTimer = nil
        clickTimer?.invalidate()
        clickTimer = nil
        haptics.stop()
    }

    private func startClicks() {
        audio.click()
        clickTimer = repeating(0.17) { $0.audio.click() }
    }

    /// A repeating main-thread timer that keeps firing while a finger is moving.
    private func repeating(_ interval: TimeInterval, _ action: @escaping @MainActor (FeedbackManager) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                action(FeedbackManager.shared)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
