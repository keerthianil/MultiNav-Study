// MultiNavStudy2App.swift
// App entry. Starts the feedback engines early so the first touch on a map
// is not delayed, carries on a session the app was closed in, and records
// app lifecycle changes in the study logs.

import SwiftUI

@main
struct MultiNavStudy2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        StudyLog.shared.appEvent("App launched", detail: AppInfo.versionDescription)
        StudyLog.shared.phaseBetweenMaps = { StudySession.shared.phaseBetweenMaps }
        StudySession.shared.resumeAfterLaunch()
        FeedbackManager.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            StudyHomeView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                FeedbackManager.shared.handleForeground()
                StudyLog.shared.appEvent("App active")
                StudyLog.shared.event(.app, "App active")
            case .background:
                FeedbackManager.shared.handleBackground()
                StudyLog.shared.appEvent("App in background")
                StudyLog.shared.event(.app, "App in background")
                StudyLog.shared.flush()
            case .inactive:
                FeedbackManager.shared.stopAll()
            @unknown default:
                break
            }
        }
    }
}

/// VoiceOver sends a magic tap to the focused element and on up the responder
/// chain, which ends at SwiftUI's own app delegate and passes nothing on. So
/// that a two-finger double tap with focus on the top bar still reaches the
/// map on screen, the map's handler is added to that delegate at launch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let delegate = application.delegate {
            Self.addMagicTap(to: type(of: delegate))
        }
        return true
    }

    /// Adds the handler only where the class has none of its own.
    static func addMagicTap(to cls: AnyClass) {
        let handler: @convention(block) (AnyObject) -> Bool = { _ in
            MainActor.assumeIsolated { MapVisit.current?.magicTapOffMap() ?? false }
        }
        _ = class_addMethod(cls, #selector(NSObject.accessibilityPerformMagicTap),
                            imp_implementationWithBlock(handler), "B@:")
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
