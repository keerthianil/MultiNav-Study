// FeedbackManager.swift
// The one place map feedback is started and stopped.
//
// Feedback is a single mode at a time. Setting a new mode stops everything
// the old one started (haptic loop, ding timer, click timer) before the new
// one begins, so moving between elements never leaves a stray vibration or
// sound running. A vibration the new mode shares with the old one carries on
// unbroken instead, so the route feels the same all along, over crosswalks,
// turns and crosswalk ends; so do the crosswalk clicks, at one steady level
// and pace over the whole crosswalk. Tones sound once, when the finger
// reaches the element (team, 11/05); only the turn dots repeat theirs.
// Setting the mode that is already playing does nothing.
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
        /// Overview intersections: slow pulse and one ding.
        case intersection
        /// Route start or end: fast pulse.
        case endpoint
        /// Route line: rhythmic pulse.
        case route
        /// Crosswalk: click every 0.17 s, with the road buzz over the road and
        /// the sidewalk buzz between the road and the corner.
        case crosswalk(overRoad: Bool)
        /// Route along a crosswalk: route pulse and crosswalk clicks.
        case routeOverCrosswalk
        /// Route turn dot: route pulse and a ding every 0.4 s.
        case turn
        /// Crosswalk end dot at a corner: one ding, with the route pulse when
        /// the dot is on the route and the sidewalk buzz otherwise, so the
        /// corner never goes still.
        case crosswalkEnd(onRoute: Bool)
        /// Centre of the intersection: the road's buzz and its own two-note
        /// chime, once.
        case center
        /// Median: fast, sharp pulses.
        case median

        /// The vibration the mode plays, if any.
        var haptic: HapticService.Pattern? {
            switch self {
            case .none: return nil
            case .road, .center: return .road
            case .sidewalk: return .sidewalk
            case .intersection: return .intersection
            case .endpoint: return .endpoint
            case .route, .routeOverCrosswalk, .turn: return .route
            case .crosswalk(let overRoad): return overRoad ? .road : .sidewalk
            case .crosswalkEnd(let onRoute): return onRoute ? .route : .sidewalk
            case .median: return .median
            }
        }

        enum Tone: Equatable { case ding, chime }

        /// The tone the mode sounds when the finger reaches it, if any.
        var tone: Tone? {
            switch self {
            case .intersection, .turn, .crosswalkEnd: return .ding
            case .center: return .chime
            case .none, .road, .sidewalk, .endpoint, .route, .crosswalk, .routeOverCrosswalk, .median: return nil
            }
        }

        /// How often the tone repeats while the finger stays, or nil when it
        /// sounds once. Only a turn dot repeats its ding.
        var toneRepeat: TimeInterval? {
            self == .turn ? 0.4 : nil
        }

        /// Whether the mode plays the crosswalk clicks.
        var clicks: Bool {
            switch self {
            case .crosswalk, .routeOverCrosswalk: return true
            default: return false
            }
        }
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
        let keepClicks = mode.clicks && newMode.clicks
        dingTimer?.invalidate()
        dingTimer = nil
        if !keepClicks {
            clickTimer?.invalidate()
            clickTimer = nil
        }
        mode = newMode
        // The haptic service keeps a pattern that is already playing running,
        // and stops the old one before starting a different one.
        if let pattern = newMode.haptic {
            haptics.play(pattern)
        } else {
            haptics.stop()
        }
        if let tone = newMode.tone {
            play(tone)
            if let interval = newMode.toneRepeat {
                dingTimer = repeating(interval) { $0.play(tone) }
            }
        }
        // Clicks already running carry on at their own pace, so crossing from
        // the corner onto the road, or onto the route over the crosswalk,
        // never adds an extra click.
        if newMode.clicks, !keepClicks {
            startClicks()
        }
    }

    private func play(_ tone: Mode.Tone) {
        switch tone {
        case .ding: audio.ding()
        case .chime: audio.chime()
        }
    }

    /// Stops all vibration and sound. Speech already under way is left to finish.
    func stopAll() {
        stopTimers()
        haptics.stop()
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

    private func stopTimers() {
        dingTimer?.invalidate()
        dingTimer = nil
        clickTimer?.invalidate()
        clickTimer = nil
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
