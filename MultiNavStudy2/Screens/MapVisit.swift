// MapVisit.swift
// One visit to one map, from opening it to the participant being ready to
// cross. It times the visit (opened, first touch, ended), counts every play
// of the announcement and of each information item, notes the information
// items in use and every change to them, and writes the visit's row to the
// visits log when it ends.

import SwiftUI
import UIKit

@MainActor
final class MapVisit: ObservableObject {
    /// The visit on screen, for gestures VoiceOver sends while its focus is
    /// off the map, on the top bar.
    private(set) static weak var current: MapVisit?

    let map: StudyMap
    let controller: (any StudyMapController)?
    let loadError: String?
    @Published private(set) var isFinished = false

    /// Closes the map screen.
    var onClose: (() -> Void)?

    private let session = StudySession.shared
    private let store = SettingsStore.shared
    private let log = StudyLog.shared
    private let feedback = FeedbackManager.shared
    private var summary: VisitSummary?
    private var started = false
    private var announcementToken = UUID()
    private var infoObserver: NSObjectProtocol?

    init(map: StudyMap) {
        self.map = map
        let settings = SettingsStore.shared.settings
        var controller: (any StudyMapController)?
        var loadError: String?
        do {
            switch map.kind {
            case .overview:
                let player = DescriptionPlayer(announcement: map.announcement, items: [])
                controller = OverviewController(map: try MapLoader.overview(named: map.file), player: player,
                                                label: map.title)
            case .intersection:
                let player = DescriptionPlayer(announcement: map.announcement, items: map.items(with: settings.info))
                controller = IntersectionController(map: try MapLoader.intersection(named: map.file), player: player,
                                                    label: Self.canvasLabel(for: map))
            }
        } catch {
            loadError = "This map could not be loaded."
            StudyLog.shared.error("\(map.file) failed to load: \(error.localizedDescription)")
        }
        controller?.showMap = settings.showMap
        self.controller = controller
        self.loadError = loadError
    }

    /// What VoiceOver reads as the map opens, before the announcement.
    static func canvasLabel(for map: StudyMap) -> String {
        switch map.phase {
        case .training: return "Training intersection map"
        case .practice: return "Practice intersection map"
        case .trial1, .trial2: return "Intersection map"
        }
    }

    // MARK: Opening

    func appear() {
        guard !started else { return }
        started = true
        let settings = store.settings
        session.startIfNeeded(participantID: settings.participantID)
        let number = session.beginVisit(map)
        let now = Date()
        let info: InfoSettings? = map.kind == .intersection ? (map.phase.usesCustomInfo ? settings.info : InfoSettings()) : nil
        log.beginMap(map, visit: number, opened: now, settings: info)
        summary = VisitSummary(phase: map.phase, mapID: map.logID, mapName: "\(map.title), \(map.subtitle)",
                               visit: number, opened: now, ended: now, endedBy: "", settingsAtOpen: info,
                               voiceOver: UIAccessibility.isVoiceOverRunning)
        feedback.setVoiceSpeed(settings.voiceSpeed)
        UIApplication.shared.isIdleTimerDisabled = true
        Self.current = self
        wire()
        announce()
    }

    /// A VoiceOver magic tap that reached the app while focus was on the top
    /// bar: the same as one on the map.
    func magicTapOffMap() -> Bool {
        guard !isFinished, let canvas = controller?.canvas else { return false }
        log.event(.gesture, "Magic tap with focus off the map")
        return canvas.accessibilityPerformMagicTap()
    }

    private func wire() {
        guard let controller else { return }
        controller.onTouchDown = { [weak self] in
            guard let self, self.summary != nil else { return }
            if self.summary?.firstTouch == nil {
                self.summary?.firstTouch = Date()
                self.log.event(.map, "First touch")
            }
            self.summary?.touches += 1
        }
        controller.onFinishRequest = { [weak self] gesture in
            guard let self else { return }
            if self.store.settings.participantCanFinish {
                self.finish(by: gesture)
            } else {
                self.log.event(.gesture, "Finish gesture ignored", detail: gesture)
                self.feedback.speak("Tell the researcher when you are ready.")
            }
        }
        controller.player.onAnnouncement = { [weak self] repeated in
            self?.summary?.announcementPlays += 1
            if repeated { self?.summary?.announcementRepeats += 1 }
        }
        controller.player.onDetailsStarted = { [weak self] in
            self?.summary?.detailActivations += 1
        }
        controller.player.onItem = { [weak self] item in
            self?.summary?.itemPlays[item.category, default: 0] += 1
        }
        if map.phase.usesCustomInfo {
            infoObserver = NotificationCenter.default.addObserver(forName: .studyInfoChanged, object: nil,
                                                                  queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.infoChanged() }
            }
        }
    }

    /// VoiceOver moves to the map and reads its name; the announcement
    /// follows once it has. Without VoiceOver the announcement plays at once.
    private func announce() {
        let token = UUID()
        announcementToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.announcementToken == token, !self.isFinished, let controller = self.controller else { return }
            if UIAccessibility.isVoiceOverRunning {
                guard let canvas = controller.canvas, canvas.window != nil else { return }
                UIAccessibility.post(notification: .screenChanged, argument: canvas)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self, self.announcementToken == token, !self.isFinished else { return }
                    self.playOpeningAnnouncement(queued: true)
                }
            } else {
                self.playOpeningAnnouncement(queued: false)
            }
        }
    }

    private func playOpeningAnnouncement(queued: Bool) {
        guard let player = controller?.player, !player.isPlaying else { return }
        player.playAnnouncement(gesture: "Map opened", repeated: false, queued: queued)
    }

    // MARK: Information items (Trial 2)

    private func infoChanged() {
        guard !isFinished, let controller else { return }
        summary?.settingsChanges += 1
        controller.player.setItems(map.items(with: store.settings.info))
    }

    func infoSheetOpened() {
        controller?.player.stop(reason: "Information settings opened")
        controller?.canvas?.reset()
        feedback.silence()
        log.event(.setting, "Information settings opened")
    }

    func infoSheetClosed() {
        log.event(.setting, "Information settings closed", detail: store.settings.info.summary)
        refocus()
    }

    /// Puts VoiceOver back on the map, after a sheet or an alert.
    func refocus() {
        guard UIAccessibility.isVoiceOverRunning, let canvas = controller?.canvas else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIAccessibility.post(notification: .layoutChanged, argument: canvas)
        }
    }

    // MARK: Ending

    /// The participant is ready to cross, or the researcher pressed Done:
    /// records the end and closes the map.
    func finish(by trigger: String) {
        guard end(by: trigger) else { return }
        session.markFinished(map)
        feedback.confirm()
        onClose?()
    }

    /// The screen went away some other way.
    func disappear() {
        end(by: "Map closed")
    }

    @discardableResult
    private func end(by trigger: String) -> Bool {
        guard started, !isFinished else { return false }
        isFinished = true
        if Self.current === self { Self.current = nil }
        announcementToken = UUID()
        controller?.player.stop(reason: trigger)
        controller?.canvas?.reset()
        feedback.silence()
        if let observer = infoObserver {
            NotificationCenter.default.removeObserver(observer)
            infoObserver = nil
        }
        if var summary {
            summary.ended = Date()
            summary.endedBy = trigger
            if summary.settingsAtOpen != nil {
                summary.settingsAtEnd = map.phase.usesCustomInfo ? store.settings.info : InfoSettings()
            }
            log.endMap(summary)
            self.summary = nil
        }
        UIApplication.shared.isIdleTimerDisabled = false
        return true
    }
}
