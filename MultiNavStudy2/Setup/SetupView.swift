// SetupView.swift
// The first screen, for the researcher: pick the route and the stage, set
// what the participant gets in that stage, and start the session. Settings
// are kept between launches. Each stage keeps its own map, direction,
// detail and feedback options; the last group applies to every stage.

import SwiftUI

enum AppScreen: Hashable {
    case session(SessionConfig)
    case intersection(SessionConfig, file: String, section: Int?)
    case files
}

struct SetupView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var path: [AppScreen] = []
    @State private var confirmReset = false

    private var stage: StudyStage { store.settings.stage }

    /// The options of the stage being set up.
    private var options: Binding<StageSettings> {
        Binding(get: { store.settings[store.settings.stage] },
                set: { store.settings[store.settings.stage] = $0 })
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                routeSection
                stageSection
                startSection
                mapSection
                directionsSection
                detailsSection
                feedbackSection
                if stage == .preJourney { timeSection }
                everyStageSection
                dataSection
            }
            .navigationTitle("Study Setup")
            .navigationDestination(for: AppScreen.self) { screen in
                switch screen {
                case .session(let config):
                    RouteMapScreen(config: config, path: $path)
                case .intersection(let config, let file, let section):
                    IntersectionScreen(config: config, file: file, sectionNumber: section)
                case .files:
                    LogFilesView()
                }
            }
            .alert("Reset all settings?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { store.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every option on this screen goes back to its default. Logs are kept.")
            }
        }
        .onChange(of: path) { _, newPath in
            let inSession = newPath.contains { if case .session = $0 { return true } else { return false } }
            if !inSession, StudyLog.shared.isSessionActive {
                StudyLog.shared.endSession(reason: "Returned to the setup screen")
                FeedbackManager.shared.silence()
                FeedbackManager.shared.configure(FeedbackManager.Options())
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    // MARK: Session

    private var routeSection: some View {
        Section {
            ForEach(RouteCatalog.routes) { route in
                let selected = route.id == store.settings.routeID
                Button {
                    store.settings.routeID = route.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Route \(route.number)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(route.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Route \(route.number), \(route.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        } header: {
            Text("Route")
        }
    }

    private var stageSection: some View {
        Section {
            Picker("Stage", selection: $store.settings.stage) {
                ForEach(StudyStage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Practice run", isOn: $store.settings.practiceRun)
        } header: {
            Text("Stage")
        } footer: {
            Text("Each stage keeps its own settings below and writes its own log files. "
                 + "A practice run is marked in the log file names.")
        }
    }

    private var startSection: some View {
        Section {
            Button {
                startSession()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Route \(selectedRouteNumber), \(stage.title)")
                        .font(.headline)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .padding(.vertical, 4)
            }
            .accessibilityHint("Opens the map. Hand the phone to the participant.")
        }
    }

    // MARK: Per-stage options

    private var mapSection: some View {
        Section {
            Picker("Map", selection: options.mapMode) {
                ForEach(MapMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Intersection close-ups", isOn: options.intersectionCloseUps)
            Toggle("Buildings at the start and destination", isOn: options.landmarks)
            Toggle("Show the map on screen", isOn: options.showMap)
        } header: {
            Text("Map, \(stage.title.lowercased())")
        } footer: {
            Text(options.wrappedValue.mapMode == .fullRoute
                 ? "The whole walk on one screen. "
                    + "Double tap an intersection to open its close-up when close-ups are on. "
                    + "With the map hidden the screen stays dark, and touch still works."
                 : "One stretch at a time, from where the traveller is (bottom) to the next intersection (top), "
                    + "turned so walking is up. Three-finger swipe up for the next section, down for the previous one. "
                    + "With the map hidden the screen stays dark, and touch still works.")
        }
    }

    private var directionsSection: some View {
        Section {
            Toggle("Turn-by-turn directions", isOn: options.turnByTurn)
            if options.wrappedValue.mapMode == .sections {
                Toggle("Speak them when a section opens", isOn: options.directionsWhenSectionOpens)
                    .disabled(!options.wrappedValue.turnByTurn)
            }
            Toggle("Spoken route overview", isOn: options.spokenOverview)
            Toggle("Distances", isOn: options.distances)
            Toggle("Side of the street", isOn: options.streetSide)
        } header: {
            Text("Directions")
        } footer: {
            Text("Directions are spoken when a section opens and when an intersection or the route is tapped once. "
                 + "The spoken overview reads the whole route when the map opens. "
                 + "A two-finger double tap repeats them.")
        }
    }

    private var detailsSection: some View {
        Section {
            Toggle("Intersection type and traffic control", isOn: options.intersectionDetails)
            Toggle("Crosswalk details", isOn: options.crosswalkDetails)
        } header: {
            Text("Details")
        } footer: {
            Text("Type and control: for example \"4-way intersection, traffic signals\". "
                 + "Crosswalk details: signals, push buttons, markings and one-way streets.")
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("Vibration", isOn: options.vibration)
            Toggle("Sounds", isOn: options.sounds)
            Toggle("Speech", isOn: options.speech)
        } header: {
            Text("Feedback")
        } footer: {
            Text("With speech off, the map only vibrates and plays sounds. "
                 + "Section numbers, time warnings and other prompts are still spoken.")
        }
    }

    private var timeSection: some View {
        Section {
            Picker("Learning time", selection: options.timeLimitMinutes) {
                ForEach(StageSettings.timeLimitChoices, id: \.self) { minutes in
                    Text(minutes == 0 ? "No limit" : "\(minutes) minutes").tag(minutes)
                }
            }
        } header: {
            Text("Time limit")
        } footer: {
            Text("The participant hears \"One minute left\" and \"Learning time is over\". "
                 + "The map stays open until you end the session.")
        }
    }

    // MARK: Every stage

    private var everyStageSection: some View {
        Section {
            Toggle("Participant can leave the map", isOn: $store.settings.participantCanLeave)
            Picker("Distances in", selection: $store.settings.units) {
                ForEach(DistanceUnits.allCases) { Text($0.title).tag($0) }
            }
            Picker("Say sides as", selection: $store.settings.sideWords) {
                ForEach(SideWords.allCases) { Text($0.title).tag($0) }
            }
            Picker("System voice speed", selection: $store.settings.voiceSpeed) {
                ForEach(VoiceSpeed.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Every stage")
        } footer: {
            Text("When participants can leave, a three-finger swipe right or the VoiceOver escape gesture on the map "
                 + "ends the session, as before. Turn it off to keep them on the map; then only End ends the session. "
                 + "Sides: \"on the northwest side\" or \"on the right-hand side\". "
                 + "The system voice is used when VoiceOver is off; VoiceOver uses its own voice and speed.")
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink(value: AppScreen.files) {
                Label("Data Files", systemImage: "doc.text")
            }
            .accessibilityHint("View, share and delete the study logs.")
            Button("Reset All Settings", role: .destructive) { confirmReset = true }
        } header: {
            Text("Data")
        } footer: {
            Text("MultiNav Study 2, \(AppInfo.versionDescription)")
        }
    }

    // MARK: Helpers

    private var selectedRouteNumber: Int {
        RouteCatalog.route(id: store.settings.routeID)?.number ?? 1
    }

    /// One line describing what the participant will get.
    private var summary: String {
        let o = options.wrappedValue
        var parts = [o.mapMode.title + " map"]
        parts.append(o.turnByTurn ? "directions on" : "directions off")
        if o.spokenOverview { parts.append("spoken overview") }
        if !o.intersectionCloseUps { parts.append("no close-ups") }
        if !o.showMap { parts.append("map hidden") }
        if !o.vibration { parts.append("no vibration") }
        if !o.sounds { parts.append("no sounds") }
        if !o.speech { parts.append("no speech") }
        if stage == .preJourney, o.timeLimitMinutes > 0 { parts.append("\(o.timeLimitMinutes) minute limit") }
        if store.settings.practiceRun { parts.append("practice") }
        return parts.joined(separator: ", ")
    }

    private func startSession() {
        guard let config = store.makeSessionConfig() else { return }
        StudyLog.shared.appEvent("Session requested", detail: "Route \(config.route.number), \(config.stageDescription)")
        path = [.session(config)]
    }
}
