// StudyHomeView.swift
// The first screen, for the researcher. It follows the study in order:
// the participant ID, then every map by phase (training, practice, Trial 1,
// Trial 2), with the information items for Trial 2 set between the trials.
// "Open next" opens the next map in study order, so between intersections
// the researcher needs one button. Any map can also be opened again, for
// example to repeat the practice; each visit is logged with its number.

import SwiftUI

enum AppScreen: Hashable {
    case map(String)
    case files
}

struct StudyHomeView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var session = StudySession.shared
    @State private var path: [AppScreen] = []
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                participantSection
                nextSection
                phaseSection(.training, header: "Training, indoors",
                             footer: "The made-up route and intersection teach the gestures; the route overview is "
                                + "the real route. Every item plays on every map here.")
                phaseSection(.practice, header: "Practice, Fore Street and Pearl Street",
                             footer: "Open it again to repeat the practice; each attempt is logged with its number.")
                phaseSection(.trial1, header: "Trial 1, every item, to Gorham's Corner",
                             footer: "Every information item plays, whatever is set below.")
                InfoSettingsSection(header: "Customization, information items for Trial 2", footer: "Trial 2 plays only the items switched on. The announcement of the "
                                    + "intersection and the route's crossings always plays, and the map's sounds "
                                    + "and vibration never change. Items can also be changed on the map, from the "
                                    + "top bar. Every change is logged.")
                phaseSection(.trial2, header: "Trial 2, chosen items, back toward the Maine Center",
                             footer: "The same intersections in reverse, each turned to the way the participant "
                                + "walks in.")
                optionsSection
                dataSection
            }
            .navigationTitle("MultiNav Study 2")
            .navigationDestination(for: AppScreen.self) { screen in
                switch screen {
                case .map(let id):
                    if let map = StudyContent.map(id: id) {
                        MapScreen(map: map, path: $path)
                    }
                case .files:
                    LogFilesView()
                }
            }
            .alert("End this session?", isPresented: $confirmEnd) {
                Button("End Session", role: .destructive) {
                    session.end(reason: "Ended by the researcher")
                    store.settings.participantID = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The logs are saved and the participant ID is cleared for the next participant.")
            }
        }
    }

    // MARK: Participant

    private var participantSection: some View {
        Section {
            if let state = session.state {
                LabeledContent("Participant", value: state.participantID.isEmpty ? "No ID" : state.participantID)
                LabeledContent("Started", value: state.started.formatted(date: .omitted, time: .shortened))
                Button("End Session", role: .destructive) { confirmEnd = true }
            } else {
                // Typed as is; the session keeps only letters, digits and hyphens.
                TextField("Participant ID", text: $store.settings.participantID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
        } header: {
            Text("Participant")
        } footer: {
            Text(session.isActive
                 ? "Every log row carries this ID. End the session before the next participant."
                 : "Letters, digits and hyphens. A session starts with the first map opened.")
        }
    }

    private var nextSection: some View {
        Section {
            if let next = session.nextMap {
                Button {
                    open(next)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Next: \(next.title)")
                            .font(.headline)
                        Text("\(next.phase.title), \(next.subtitle)")
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityHint("Opens the map. Hand the phone to the participant.")
            } else {
                Text("Every map has been explored. End the session when the participant is done.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Phases

    private func phaseSection(_ phase: StudyPhase, header: String, footer: String) -> some View {
        Section {
            ForEach(StudyContent.maps(in: phase)) { map in
                MapRow(map: map, visits: session.visits(map), finished: session.isFinished(map),
                       isNext: session.nextMap?.id == map.id) {
                    open(map)
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    // MARK: Options and data

    private var optionsSection: some View {
        Section {
            Toggle("Participant can finish with a gesture", isOn: $store.settings.participantCanFinish)
            Picker("System voice speed", selection: $store.settings.voiceSpeed) {
                ForEach(VoiceSpeed.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show the map on screen", isOn: $store.settings.showMap)
        } header: {
            Text("Options")
        } footer: {
            Text("With the gesture on, a three-finger swipe right (or the VoiceOver escape) means the participant is "
                 + "ready to cross: the end time is logged and the map closes, as with Done. The system voice is "
                 + "used when VoiceOver is off; VoiceOver uses its own voice and speed. With the map hidden the "
                 + "screen stays dark, and touch, sound and vibration still work.")
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink(value: AppScreen.files) {
                Label("Data Files", systemImage: "doc.text")
            }
            .accessibilityHint("View, share and delete the study logs.")
        } header: {
            Text("Data")
        } footer: {
            Text("MultiNav Study 2, \(AppInfo.versionDescription)")
        }
    }

    private func open(_ map: StudyMap) {
        StudyLog.shared.appEvent("Map requested", detail: map.logID)
        path = [.map(map.id)]
    }
}

/// One map on the first screen: its title and streets, how often it has
/// been opened, and whether it is next.
private struct MapRow: View {
    let map: StudyMap
    let visits: Int
    let finished: Bool
    let isNext: Bool
    let action: () -> Void

    private var status: String {
        if visits == 0 { return isNext ? "Next" : "" }
        if map.phase == .practice { return visits == 1 ? "1 attempt" : "\(visits) attempts" }
        return visits == 1 ? "Opened once" : "Opened \(visits) times"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(map.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(map.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !status.isEmpty {
                    Text(status)
                        .font(.caption.weight(isNext ? .bold : .regular))
                        .foregroundStyle(isNext ? Color.accentColor : .secondary)
                }
                if finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(map.title), \(map.subtitle)")
        .accessibilityValue([status, finished ? "explored" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// The six information items, each on or off, for Trial 2. Shared by the
/// first screen and the map's Information sheet.
struct InfoSettingsSection: View {
    @ObservedObject private var store = SettingsStore.shared
    var header = "Information items for Trial 2"
    let footer: String

    var body: some View {
        Section {
            ForEach(InfoCategory.allCases) { category in
                Toggle(isOn: Binding(get: { store.settings.info[category] },
                                     set: { store.setInfo(category, $0) })) {
                    Text("\(category.number). \(category.title)")
                }
            }
            Button("Turn All On") { store.allInfoOn() }
                .disabled(store.settings.info.allOn)
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }
}
