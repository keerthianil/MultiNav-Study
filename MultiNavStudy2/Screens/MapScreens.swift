// MapScreens.swift
// The two map screens. The route map shows the whole walk or one section of
// it; double tapping an intersection pushes its close-up.
//
// The route map has no Back button: the researcher ends the session with
// End (and a confirmation), so a participant cannot land on the setup screen
// by accident. Participants leave with gestures only if the setup allows it.

import SwiftUI
import UIKit

typealias MapController = MapScene & TactileCanvasDelegate

/// Hosts a TactileCanvasView full screen, keeping the drawing clear of the
/// navigation bar and home indicator.
struct TactileMapContainer: UIViewRepresentable {
    let controller: any MapController
    let label: String
    let hint: String
    let insets: EdgeInsets
    let onMake: (TactileCanvasView) -> Void

    func makeUIView(context: Context) -> TactileCanvasView {
        let canvas = TactileCanvasView(frame: .zero)
        canvas.scene = controller
        canvas.delegate = controller
        canvas.configureAccessibility(label: label, hint: hint)
        onMake(canvas)
        return canvas
    }

    func updateUIView(_ canvas: TactileCanvasView, context: Context) {
        canvas.contentInsets = UIEdgeInsets(top: insets.top, left: insets.leading,
                                            bottom: insets.bottom, right: insets.trailing)
    }
}

/// Moves VoiceOver to the map so it reads the screen's name, or speaks the
/// name when VoiceOver is off, then speaks any follow-up (a route overview or
/// a section's directions) after it. Each screen has its own pending
/// announcement, cancelled when that screen disappears, so a screen already
/// left never speaks over the next one.
@MainActor
enum ScreenAnnouncer {
    private static var pending: [String: UUID] = [:]

    static func announce(screen: String, canvas: @escaping () -> TactileCanvasView?, spoken: String,
                         followUp: String = "", delay: TimeInterval = 0.6) {
        let token = UUID()
        pending[screen] = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pending[screen] == token else { return }
            pending[screen] = nil
            if UIAccessibility.isVoiceOverRunning {
                guard let canvas = canvas(), canvas.window != nil else { return }
                UIAccessibility.post(notification: .screenChanged, argument: canvas)
            } else {
                FeedbackManager.shared.speak(spoken, essential: true)
            }
            if !followUp.isEmpty {
                FeedbackManager.shared.speak(followUp, queued: true)
            }
        }
    }

    static func cancel(screen: String) {
        pending[screen] = nil
    }
}

// MARK: - Route map

struct RouteMapScreen: View {
    let config: SessionConfig
    @Binding var path: [AppScreen]
    @StateObject private var session: RouteSession
    @State private var confirmEnd = false

    init(config: SessionConfig, path: Binding<[AppScreen]>) {
        self.config = config
        _path = path
        _session = StateObject(wrappedValue: RouteSession(config: config))
    }

    var body: some View {
        ZStack {
            (config.options.showMap ? Color.white : Color.black).ignoresSafeArea()
            if let controller = session.controller {
                GeometryReader { proxy in
                    TactileMapContainer(controller: controller, label: controller.accessibilityLabel,
                                        hint: controller.accessibilityHint, insets: proxy.safeAreaInsets) { canvas in
                        controller.canvas = canvas
                    }
                    .ignoresSafeArea()
                }
            } else if let loadError = session.loadError {
                MapLoadErrorView(message: loadError)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("End") { confirmEnd = true }
                    .accessibilityHint("Ends the session after you confirm.")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(session.title).font(.headline)
                    if let remaining = session.remainingText {
                        Text(remaining).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if session.isSectionMode {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        session.moveSection(forward: false, gesture: "Previous section button")
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Previous section")
                    Button {
                        session.moveSection(forward: true, gesture: "Next section button")
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .accessibilityLabel("Next section")
                }
            }
        }
        .alert("End this session?", isPresented: $confirmEnd) {
            Button("End Session", role: .destructive) { session.end(reason: "Ended by the researcher") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The logs for this session are saved.")
        }
        .onAppear {
            session.onOpenIntersection = { file in
                path.append(.intersection(config, file: file, section: session.currentSection?.index))
            }
            session.onLeave = { path.removeAll() }
            session.appear()
        }
        .onDisappear { session.disappear() }
        .disableInteractivePopGesture()
    }
}

// MARK: - Intersection close-up

struct IntersectionScreen: View {
    let config: SessionConfig
    let file: String
    /// The section the close-up was opened from, for the logs.
    let sectionNumber: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var controller: DetailController?
    @State private var loadError: String?

    init(config: SessionConfig, file: String, sectionNumber: Int?) {
        self.config = config
        self.file = file
        self.sectionNumber = sectionNumber
        do {
            let map = try MapLoader.detail(named: file)
            let directions = try? RouteDirections.load(named: config.route.directions)
            let composer = directions.map { DirectionsComposer(directions: $0, config: config) }
            let section = directions?.section(withDetail: file)
            _controller = State(initialValue: DetailController(config: config, map: map, composer: composer, section: section))
        } catch {
            _loadError = State(initialValue: "This intersection could not be loaded.")
            StudyLog.shared.error("Intersection \(file) failed to load: \(error.localizedDescription)")
        }
    }

    var body: some View {
        ZStack {
            (config.options.showMap ? Color.white : Color.black).ignoresSafeArea()
            if let controller {
                GeometryReader { proxy in
                    TactileMapContainer(controller: controller, label: controller.accessibilityLabel,
                                        hint: controller.accessibilityHint, insets: proxy.safeAreaInsets) { canvas in
                        controller.canvas = canvas
                    }
                    .ignoresSafeArea()
                }
            } else if let loadError {
                MapLoadErrorView(message: loadError)
            }
        }
        .navigationTitle(controller?.map.isRoundabout == true ? "Roundabout" : "Intersection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear(perform: appear)
        .onDisappear {
            ScreenAnnouncer.cancel(screen: "intersection")
            controller?.canvas?.reset()
            FeedbackManager.shared.silence()
        }
        .disableInteractivePopGesture()
    }

    private func appear() {
        guard let controller else { return }
        StudyLog.shared.setView(.intersection, section: sectionNumber,
                                condition: "Route \(config.route.number), \(config.stageDescription), "
                                    + "intersection view (\(controller.map.title))")
        controller.screenDidAppear()
        controller.onBack = { dismiss() }
        ScreenAnnouncer.announce(screen: "intersection", canvas: { [weak controller] in controller?.canvas },
                                 spoken: controller.intro)
    }
}

private struct MapLoadErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
            Text("The problem is recorded in the app log.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
