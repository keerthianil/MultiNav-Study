// RouteSession.swift
// One session on one route: the map shown (the full route or the current
// section), moving between sections, the learning time limit, the lock that
// keeps participants on the map, and the log session.

import SwiftUI
import UIKit

@MainActor
final class RouteSession: ObservableObject {
    let config: SessionConfig
    let directions: RouteDirections?
    let composer: DirectionsComposer?
    let controller: OverviewController?
    let loadError: String?

    /// Index into the route's sections, in section by section mode.
    @Published private(set) var sectionIndex = 0
    /// Seconds of learning time left, when there is a limit.
    @Published private(set) var remainingSeconds: Int?

    /// Opens an intersection close-up (by file name).
    var onOpenIntersection: ((String) -> Void)?
    /// Leaves the map and returns to the setup screen.
    var onLeave: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared
    private var sectionMaps: [Int: OverviewMap] = [:]
    private var timer: Timer?
    private var started = false
    private var ended = false

    init(config: SessionConfig) {
        self.config = config
        var directions: RouteDirections?
        var composer: DirectionsComposer?
        var controller: OverviewController?
        var firstSectionMap: OverviewMap?
        var loadError: String?
        do {
            let loaded = try RouteDirections.load(named: config.route.directions)
            let words = DirectionsComposer(directions: loaded, config: config)
            let map: OverviewMap
            var section: RouteDirections.Section?
            if config.mapMode == .sections {
                guard let first = loaded.sections.first else {
                    throw MapLoadError.missing(config.route.directions, "sections")
                }
                map = try MapLoader.overview(named: first.map)
                section = first
                firstSectionMap = map
            } else {
                map = try MapLoader.overview(named: config.route.overview)
            }
            directions = loaded
            composer = words
            controller = OverviewController(config: config, composer: words, map: map, section: section)
        } catch {
            loadError = "The map for route \(config.route.number) could not be loaded."
            StudyLog.shared.error("Route \(config.route.number) failed to load: \(error.localizedDescription)")
        }
        self.directions = directions
        self.composer = composer
        self.controller = controller
        self.loadError = loadError
        if let firstSectionMap { sectionMaps[0] = firstSectionMap }
        wireController()
    }

    var isSectionMode: Bool { config.mapMode == .sections }

    var currentSection: RouteDirections.Section? {
        guard isSectionMode, let sections = directions?.sections, sections.indices.contains(sectionIndex) else { return nil }
        return sections[sectionIndex]
    }

    var title: String {
        if let section = currentSection {
            return "Route \(config.route.number), \(section.index) of \(section.count)"
        }
        return "Route \(config.route.number)"
    }

    var remainingText: String? {
        guard let remainingSeconds else { return nil }
        if remainingSeconds <= 0 { return "Time is up" }
        return String(format: "%d:%02d left", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var condition: String {
        var text = "Route \(config.route.number), \(config.stageDescription), \(config.mapMode.title.lowercased())"
        if let section = currentSection { text += ", section \(section.index) of \(section.count)" }
        return text
    }

    // MARK: Appearing

    /// Called each time the map screen appears, including after a close-up.
    func appear() {
        guard controller != nil else {
            if !started {
                started = true
                log.startSession(config: config)
            }
            return
        }
        if !started {
            started = true
            log.startSession(config: config)
            feedback.configure(FeedbackManager.Options(vibration: config.options.vibration,
                                                       sounds: config.options.sounds,
                                                       speech: config.options.speech,
                                                       voiceSpeed: config.voiceSpeed))
            UIApplication.shared.isIdleTimerDisabled = true
            recordView()
            startTimer()
            announceOpening()
        } else {
            recordView()
            announceReturn()
        }
    }

    private func recordView() {
        log.setView(isSectionMode ? .section : .fullRoute, section: currentSection?.index, condition: condition)
    }

    private func announceOpening() {
        guard let composer, let canvas = controller?.canvas else { return }
        var spoken: [String] = []
        if config.options.spokenOverview { spoken.append(composer.overview()) }
        if let section = currentSection {
            let withDirections = config.options.turnByTurn && config.options.directionsWhenSectionOpens
            spoken.append(withDirections ? composer.directionsText(section) : composer.brief(section))
            ScreenAnnouncer.announce(screen: "map", canvas: { [weak canvas] in canvas },
                                     spoken: composer.sectionStatus(section), followUp: spoken.joined(separator: " "))
        } else {
            ScreenAnnouncer.announce(screen: "map", canvas: { [weak canvas] in canvas },
                                     spoken: "Map overview", followUp: spoken.joined(separator: " "))
        }
    }

    private func announceReturn() {
        guard let canvas = controller?.canvas else { return }
        let status = currentSection.map { composer?.sectionStatus($0) ?? "" } ?? "Map overview"
        ScreenAnnouncer.announce(screen: "map", canvas: { [weak canvas] in canvas }, spoken: status, followUp: "")
    }

    func disappear() {
        ScreenAnnouncer.cancel(screen: "map")
        controller?.canvas?.reset()
        feedback.silence()
    }

    // MARK: Sections

    /// Moves to the next or previous section. Returns false at either end.
    @discardableResult
    func moveSection(forward: Bool, gesture: String) -> Bool {
        guard isSectionMode, let directions, let composer, let controller else { return false }
        let target = sectionIndex + (forward ? 1 : -1)
        let name = forward ? "Next section" : "Previous section"
        guard directions.sections.indices.contains(target) else {
            log.event(.section, name, detail: "\(gesture), already at the \(forward ? "last" : "first") section")
            feedback.speak(forward ? "This is the last section." : "This is the first section.", essential: true)
            return false
        }
        let section = directions.sections[target]
        let map: OverviewMap
        do {
            map = try sectionMaps[target] ?? MapLoader.overview(named: section.map)
        } catch {
            log.error("Section map \(section.map) failed to load: \(error.localizedDescription)")
            feedback.speak("This section could not be loaded.", essential: true)
            return false
        }
        sectionMaps[target] = map
        sectionIndex = target
        controller.show(map: map, section: section)
        feedback.backTap()
        log.event(.section, name, detail: "Section \(section.index) of \(section.count), \(gesture)")
        recordView()
        let withDirections = config.options.turnByTurn && config.options.directionsWhenSectionOpens
        feedback.speakPageStatus(composer.sectionIntro(section, withDirections: withDirections))
        return true
    }

    // MARK: Gestures

    func magicTap() {
        guard let composer else { return }
        if let section = currentSection {
            log.event(.gesture, "Magic tap", detail: "Section directions")
            feedback.speak(composer.sectionIntro(section, withDirections: config.options.turnByTurn), essential: true)
        } else if config.options.spokenOverview {
            log.event(.gesture, "Magic tap", detail: "Route overview")
            feedback.speak(composer.overview(), essential: true)
        } else {
            log.event(.gesture, "Magic tap", detail: "Route summary")
            feedback.speak(composer.summary(), essential: true)
        }
    }

    /// A back gesture on the map. Leaves only if participants may.
    func requestLeave(gesture: String) {
        guard config.participantCanLeave else {
            log.event(.gesture, "Back blocked", detail: gesture)
            feedback.speak("The map is locked. Ask the researcher to end the session.", essential: true)
            return
        }
        log.event(.gesture, "Back", detail: gesture)
        end(reason: "Participant left the map")
    }

    // MARK: Time limit

    private func startTimer() {
        let limit = config.timeLimitSeconds
        guard limit > 0 else { return }
        remainingSeconds = limit
        log.event(.timer, "Time limit started", detail: "\(config.options.timeLimitMinutes) minutes")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let remaining = remainingSeconds, remaining > 0 else { return }
        let now = remaining - 1
        remainingSeconds = now
        if now == 60, config.timeLimitSeconds > 60 {
            log.event(.timer, "One minute left")
            feedback.speak("One minute left.", essential: true)
        } else if now == 0 {
            log.event(.timer, "Time is up")
            feedback.speak("Learning time is over.", essential: true)
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Ending

    /// Ends the session and returns to the setup screen.
    func end(reason: String) {
        guard !ended else { return }
        ended = true
        timer?.invalidate()
        timer = nil
        ScreenAnnouncer.cancel(screen: "map")
        controller?.canvas?.reset()
        feedback.silence()
        feedback.configure(FeedbackManager.Options())
        log.endSession(reason: reason)
        UIApplication.shared.isIdleTimerDisabled = false
        onLeave?()
    }

    private func wireController() {
        guard let controller else { return }
        controller.onOpenIntersection = { [weak self] intersection in
            guard let self else { return }
            self.log.event(.screen, "Open intersection", detail: intersection.name)
            self.onOpenIntersection?(intersection.detailFile)
        }
        controller.onBack = { [weak self] gesture in self?.requestLeave(gesture: gesture) }
        controller.onSection = { [weak self] forward, gesture in
            self?.moveSection(forward: forward, gesture: gesture) ?? false
        }
        controller.onMagicTap = { [weak self] in self?.magicTap() }
    }
}
