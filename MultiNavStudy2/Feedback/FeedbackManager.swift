// FeedbackManager.swift
// The one place map feedback is started and stopped.
//
// Feedback is a single mode at a time. Setting a new mode stops everything
// the old one started (haptic loop, ding timer, click timer) before the new
// one begins, so moving between elements never leaves a stray vibration or
// sound running. Setting the mode that is already playing does nothing.
//
// Speech is separate. A map name cuts off the name before it; the
// intersection descriptions are spoken through `speakTracked`, which says
// when each phrase ends so the next item can follow.

import UIKit

@MainActor
final class FeedbackManager {
    static let shared = FeedbackManager()

    enum Mode: Equatable {
        case none
        /// Streets: steady heavy buzz.
        case road
        /// Sidewalks: softer steady buzz.
        case sidewalk
        /// Overview intersections: slow pulse and a ding every 0.4 s.
        case intersection
        /// Route start or end: fast pulse.
        case endpoint
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
        /// Centre of the intersection: its own two-note chime, and no vibration.
        case center
        /// Median: fast, sharp pulses.
        case median
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

    /// The speed of the system voice, used when VoiceOver is off.
    func setVoiceSpeed(_ speed: VoiceSpeed) {
        speech.rateMultiplier = speed.rateMultiplier
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
        case .endpoint:
            haptics.play(.endpoint)
        case .route:
            haptics.play(.route)
        case .crosswalk(let overRoad):
            if overRoad { haptics.play(.road) }
            startClicks()
        case .routeOverCrosswalk:
            haptics.play(.route)
            startClicks()
        case .turn:
            turnDing()
            dingTimer = repeating(0.4) { $0.turnDing() }
        case .crosswalkEnd:
            audio.ding()
        case .center:
            audio.chime()
            dingTimer = repeating(0.7) { $0.audio.chime() }
        case .median:
            haptics.play(.median)
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
    /// are not repeated. A queued phrase waits for the current speech.
    func speak(_ text: String, queued: Bool = false) {
        guard !text.isEmpty else { return }
        let now = CACurrentMediaTime()
        if text == lastSpoken.text, now - lastSpoken.time < 0.5 { return }
        lastSpoken = (text, now)
        speech.speak(text, queued: queued)
        StudyLog.shared.event(.speech, text)
    }

    /// Speaks a part of a description and reports when it ends: true when it
    /// was heard to the end, false when something cut it off.
    func speakTracked(_ text: String, queued: Bool = false, completion: @escaping (Bool) -> Void) {
        lastSpoken = (text, CACurrentMediaTime())
        speech.speak(text, queued: queued) { finished in
            MainActor.assumeIsolated { completion(finished) }
        }
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

    /// Confirms a gesture such as finishing or moving between items.
    func confirm() {
        haptics.turnTap()
    }

    /// A low tone when there is no item further that way.
    func boundary() {
        audio.boundary()
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
