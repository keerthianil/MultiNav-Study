// MapScreen.swift
// A map, full screen, for the participant. The top bar is for the
// researcher: Done when the participant is ready to cross, and in Trial 2
// the information items, which can be changed at any intersection.
//
// There is no Back button. Done asks for confirmation when VoiceOver is off,
// so a stray tap at the top of the screen cannot end the visit; with
// VoiceOver on, its double tap is already deliberate.

import SwiftUI
import UIKit

/// Hosts a TactileCanvasView full screen, keeping the drawing clear of the
/// navigation bar and home indicator.
struct TactileMapContainer: UIViewRepresentable {
    let controller: any StudyMapController
    let insets: EdgeInsets
    let onMake: (TactileCanvasView) -> Void

    func makeUIView(context: Context) -> TactileCanvasView {
        let canvas = TactileCanvasView(frame: .zero)
        canvas.scene = controller
        canvas.delegate = controller
        canvas.configureAccessibility(label: controller.canvasLabel)
        onMake(canvas)
        return canvas
    }

    func updateUIView(_ canvas: TactileCanvasView, context: Context) {
        canvas.contentInsets = UIEdgeInsets(top: insets.top, left: insets.leading,
                                            bottom: insets.bottom, right: insets.trailing)
    }
}

struct MapScreen: View {
    let map: StudyMap
    @Binding var path: [AppScreen]
    @StateObject private var visit: MapVisit
    @ObservedObject private var store = SettingsStore.shared
    @State private var confirmDone = false
    @State private var showInfo = false

    init(map: StudyMap, path: Binding<[AppScreen]>) {
        self.map = map
        _path = path
        _visit = StateObject(wrappedValue: MapVisit(map: map))
    }

    var body: some View {
        ZStack {
            (store.settings.showMap ? Color.white : Color.black).ignoresSafeArea()
            if let controller = visit.controller {
                GeometryReader { proxy in
                    TactileMapContainer(controller: controller, insets: proxy.safeAreaInsets) { canvas in
                        controller.canvas = canvas
                    }
                    .ignoresSafeArea()
                }
            } else if let loadError = visit.loadError {
                MapLoadErrorView(message: loadError)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    if UIAccessibility.isVoiceOverRunning {
                        visit.finish(by: "Done button")
                    } else {
                        confirmDone = true
                    }
                }
                .accessibilityHint("Records that the participant is ready to cross, and closes the map.")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(map.title).font(.headline)
                    Text(map.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if map.phase.usesCustomInfo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        visit.infoSheetOpened()
                        showInfo = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Information items")
                    .accessibilityHint("Switch information items on or off for this intersection.")
                }
            }
        }
        .alert("Finish exploring?", isPresented: $confirmDone) {
            Button("Finish") { visit.finish(by: "Done button") }
            Button("Keep Exploring", role: .cancel) { visit.refocus() }
        } message: {
            Text("This records when the participant was ready to cross, and closes the map.")
        }
        .sheet(isPresented: $showInfo, onDismiss: { visit.infoSheetClosed() }) {
            InfoSheet()
        }
        .onAppear {
            visit.onClose = { [map] in
                if case .map(map.id) = path.last { path.removeLast() }
            }
            visit.appear()
        }
        .onDisappear { visit.disappear() }
        .disableInteractivePopGesture()
    }
}

/// The information items, opened from the top bar during Trial 2.
private struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                InfoSettingsSection(footer: "Changes apply on this map from the next double tap, and to every "
                                    + "Trial 2 intersection after it. Each change is logged.")
            }
            .navigationTitle("Information Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
