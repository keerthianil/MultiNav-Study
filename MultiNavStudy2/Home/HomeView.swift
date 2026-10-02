// HomeView.swift
// Main menu: the four routes and the data files.

import SwiftUI

enum AppScreen: Hashable {
    case route(String)
    case intersection(routeID: String, file: String)
    case files
}

struct HomeView: View {
    @State private var path: [AppScreen] = []

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
        VStack(alignment: .leading, spacing: 3) {
            Text("Route \(route.number)")
                .font(.title3.weight(.semibold))
            Text(route.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route \(route.number), \(route.title)")
    }
}
