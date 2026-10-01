// HomeView.swift
// Main menu: the four routes, an optional participant ID for the log file
// names, and the data files.

import SwiftUI

enum AppScreen: Hashable {
    case route(String)
    case intersection(routeID: String, file: String)
    case files
}

struct HomeView: View {
    @State private var path: [AppScreen] = []
    @AppStorage(StudyLog.participantKey) private var participantID = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(RouteCatalog.routes) { route in
                        NavigationLink(value: AppScreen.route(route.id)) {
                            RouteRow(route: route)
                        }
                        .accessibilityHint("Opens the tactile map for this route.")
                    }
                } header: {
                    Text("Routes")
                }

                Section {
                    TextField("Participant ID", text: $participantID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityHint("Optional. Added to the names of new log files.")
                } header: {
                    Text("Participant")
                } footer: {
                    Text("Optional. Added to the names of new log files.")
                }

                Section {
                    NavigationLink(value: AppScreen.files) {
                        Label("Data Files", systemImage: "doc.text")
                    }
                    .accessibilityHint("View, share and delete the study logs.")
                } header: {
                    Text("Tools")
                } footer: {
                    Text("MultiNav Study 2, \(AppInfo.versionDescription)")
                }
            }
            .navigationTitle("MultiNav Study 2")
            .navigationDestination(for: AppScreen.self) { screen in
                switch screen {
                case .route(let id):
                    if let route = RouteCatalog.route(id: id) {
                        RouteMapScreen(route: route, path: $path)
                    }
                case .intersection(let routeID, let file):
                    if let route = RouteCatalog.route(id: routeID) {
                        IntersectionScreen(route: route, file: file)
                    }
                case .files:
                    LogFilesView()
                }
            }
        }
        .onChange(of: path) { _, newPath in
            let onRoute = newPath.contains { if case .route = $0 { return true } else { return false } }
            if !onRoute {
                StudyLog.shared.endSession()
                FeedbackManager.shared.silence()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

private struct RouteRow: View {
    let route: RouteInfo

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(route.number)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.title)
                    .font(.headline)
                Text(route.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route \(route.number). \(route.title). \(route.summary)")
    }
}
