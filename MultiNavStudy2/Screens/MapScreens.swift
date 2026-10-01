// MapScreens.swift
// The two map screens. Level 1 shows a whole route; double tapping one of
// its intersections pushes Level 2, the close-up of that intersection.

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
/// name when VoiceOver is off. Each screen has its own pending announcement,
/// cancelled when that screen disappears, so a screen already left never
/// speaks over the next one.
@MainActor
enum ScreenAnnouncer {
    private static var pending: [String: UUID] = [:]

    static func announce(screen: String, canvas: @escaping () -> TactileCanvasView?, spoken: String,
                         delay: TimeInterval = 0.6) {
        let token = UUID()
        pending[screen] = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pending[screen] == token else { return }
            pending[screen] = nil
            if UIAccessibility.isVoiceOverRunning {
                guard let canvas = canvas(), canvas.window != nil else { return }
                UIAccessibility.post(notification: .screenChanged, argument: canvas)
            } else {
                FeedbackManager.shared.speak(spoken)
            }
        }
    }

    static func cancel(screen: String) {
        pending[screen] = nil
    }
}

// MARK: - Level 1

struct RouteMapScreen: View {
    let route: RouteInfo
    @Binding var path: [AppScreen]
    @Environment(\.dismiss) private var dismiss
    @State private var controller: OverviewController?
    @State private var loadError: String?

    init(route: RouteInfo, path: Binding<[AppScreen]>) {
        self.route = route
        _path = path
        do {
            let map = try MapLoader.overview(named: route.overview)
            _controller = State(initialValue: OverviewController(route: route, map: map))
        } catch {
            _loadError = State(initialValue: "The map for route \(route.number) could not be loaded.")
            StudyLog.shared.error("Overview \(route.overview) failed to load: \(error.localizedDescription)")
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
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
        .navigationTitle("Route \(route.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear(perform: appear)
        .onDisappear {
            ScreenAnnouncer.cancel(screen: "overview")
            controller?.canvas?.reset()
            FeedbackManager.shared.silence()
        }
        .disableInteractivePopGesture()
    }

    private func appear() {
        StudyLog.shared.startSession(route: route)
        guard let controller else { return }
        StudyLog.shared.setCondition("Route \(route.number) - Map Overview")
        UIApplication.shared.isIdleTimerDisabled = true
        controller.screenDidAppear()
        controller.onOpenIntersection = { intersection in
            StudyLog.shared.event(.screen, "Open intersection", detail: intersection.name)
            path.append(.intersection(routeID: route.id, file: intersection.detailFile))
        }
        controller.onBack = { dismiss() }
        ScreenAnnouncer.announce(screen: "overview", canvas: { [weak controller] in controller?.canvas },
                                 spoken: "Map overview")
    }
}

// MARK: - Level 2

struct IntersectionScreen: View {
    let route: RouteInfo
    let file: String
    @Environment(\.dismiss) private var dismiss
    @State private var controller: DetailController?
    @State private var loadError: String?

    init(route: RouteInfo, file: String) {
        self.route = route
        self.file = file
        do {
            _controller = State(initialValue: DetailController(route: route, map: try MapLoader.detail(named: file)))
        } catch {
            _loadError = State(initialValue: "This intersection could not be loaded.")
            StudyLog.shared.error("Intersection \(file) failed to load: \(error.localizedDescription)")
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
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
        StudyLog.shared.setCondition("Route \(route.number) - Intersection View (\(controller.map.title))")
        controller.screenDidAppear()
        controller.onBack = { dismiss() }
        ScreenAnnouncer.announce(screen: "intersection", canvas: { [weak controller] in controller?.canvas },
                                 spoken: controller.map.intro)
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
