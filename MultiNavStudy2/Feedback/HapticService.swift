// HapticService.swift
// Core Haptics patterns for the map. One looping pattern plays at a time;
// starting another stops the last one, so two never overlap.
//
//   road        steady heavy buzz          intensity 1.0, sharpness 0.10
//   sidewalk    softer steady buzz         intensity 0.78, sharpness 0.78
//   intersection slow pulse 0.15 s every 0.25 s, intensity 1.0, sharpness 0.5
//   endpoint    fast pulse 0.08 s every 0.12 s, intensity 1.0, sharpness 0.7
//   route       rhythmic pulse 0.12 s every 0.2 s, intensity 1.0, sharpness 0.85
//   median      fast, sharp taps, one every 0.08 s, intensity 1.0, sharpness 0.9
// The centre of an intersection has no vibration at all.

import CoreHaptics
import UIKit

final class HapticService {
    enum Pattern: Equatable {
        case road, sidewalk, intersection, endpoint, route, median
    }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var current: Pattern?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var cache: [Pattern: (pattern: CHHapticPattern, loopEnd: TimeInterval)] = [:]
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// Called with a message whenever the engine fails, for the study log.
    var onError: ((String) -> Void)?

    init() {
        guard supportsHaptics else { return }
        buildPatterns()
        makeEngine()
    }

    // MARK: Engine

    private func makeEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] reason in
                DispatchQueue.main.async { self?.engineStopped(reason) }
            }
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async { self?.engineReset() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
            onError?("Haptic engine failed to start: \(error.localizedDescription)")
        }
    }

    private func engineStopped(_ reason: CHHapticEngine.StoppedReason) {
        player = nil
        // In the background the engine is meant to stop; it restarts when the
        // app is active again.
        guard UIApplication.shared.applicationState == .active else { return }
        onError?("Haptic engine stopped (reason \(reason.rawValue))")
        restart()
    }

    private func engineReset() {
        player = nil
        guard UIApplication.shared.applicationState == .active else { return }
        restart()
    }

    /// Restarts the engine and resumes whatever pattern was playing.
    func restart() {
        guard supportsHaptics else { return }
        if engine == nil { makeEngine() }
        do {
            try engine?.start()
        } catch {
            engine = nil
            makeEngine()
        }
        if let pattern = current {
            current = nil
            play(pattern)
        }
    }

    func suspend() {
        stop()
        engine?.stop(completionHandler: nil)
    }

    // MARK: Patterns

    func play(_ pattern: Pattern) {
        guard supportsHaptics, pattern != current else { return }
        stopPlayer()
        current = pattern
        guard let engine, let entry = cache[pattern] else { return }
        do {
            let player = try engine.makeAdvancedPlayer(with: entry.pattern)
            player.loopEnabled = true
            player.loopEnd = entry.loopEnd
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
        } catch {
            onError?("Haptic pattern \(pattern) failed: \(error.localizedDescription)")
            restartAfterFailure(pattern)
        }
    }

    private func restartAfterFailure(_ pattern: Pattern) {
        current = nil
        do {
            try engine?.start()
            guard let engine, let entry = cache[pattern] else { return }
            let player = try engine.makeAdvancedPlayer(with: entry.pattern)
            player.loopEnabled = true
            player.loopEnd = entry.loopEnd
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            current = pattern
        } catch {
            onError?("Haptic retry failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        current = nil
        stopPlayer()
    }

    private func stopPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// One sharp tap, used for single taps on the map.
    func tap() {
        guard supportsHaptics, let engine else {
            rigid.impactOccurred()
            return
        }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            rigid.impactOccurred()
        }
    }

    /// Light tap with the turn ding, and to confirm a gesture.
    func turnTap() {
        impact.impactOccurred(intensity: 0.9)
        impact.prepare()
    }

    private func buildPatterns() {
        func continuous(_ intensity: Float, _ sharpness: Float) -> (CHHapticPattern, TimeInterval)? {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0, duration: 2.0)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []) else { return nil }
            return (pattern, 2.0)
        }
        func pulsing(on: TimeInterval, every period: TimeInterval, _ intensity: Float, _ sharpness: Float) -> (CHHapticPattern, TimeInterval)? {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0, duration: on)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []) else { return nil }
            return (pattern, period)
        }
        func taps(every period: TimeInterval, count: Int, _ intensity: Float, _ sharpness: Float) -> (CHHapticPattern, TimeInterval)? {
            let events = (0..<count).map { i in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: period * Double(i))
            }
            guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return nil }
            return (pattern, period * Double(count))
        }
        let all: [(Pattern, (CHHapticPattern, TimeInterval)?)] = [
            (.road, continuous(1.0, 0.1)),
            (.sidewalk, continuous(0.78, 0.78)),
            (.intersection, pulsing(on: 0.15, every: 0.25, 1.0, 0.5)),
            (.endpoint, pulsing(on: 0.08, every: 0.12, 1.0, 0.7)),
            (.route, pulsing(on: 0.12, every: 0.2, 1.0, 0.85)),
            (.median, taps(every: 0.08, count: 4, 1.0, 0.9)),
        ]
        for (key, value) in all {
            if let value { cache[key] = (value.0, value.1) }
        }
        impact.prepare()
    }
}
