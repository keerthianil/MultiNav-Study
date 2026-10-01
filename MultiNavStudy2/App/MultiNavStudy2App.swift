// MultiNavStudy2App.swift
// App entry. Starts the feedback engines early so the first touch on a map
// is not delayed, and records app lifecycle changes in the study logs.

import SwiftUI

@main
struct MultiNavStudy2App: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        StudyLog.shared.appEvent("App launched", detail: AppInfo.versionDescription)
        FeedbackManager.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                FeedbackManager.shared.handleForeground()
                StudyLog.shared.appEvent("App active")
            case .background:
                FeedbackManager.shared.handleBackground()
                StudyLog.shared.appEvent("App in background")
                StudyLog.shared.flush()
            case .inactive:
                FeedbackManager.shared.stopAll()
            @unknown default:
                break
            }
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var versionDescription: String {
        "Version \(version) (\(build)), iOS \(UIDevice.current.systemVersion)"
    }
}
