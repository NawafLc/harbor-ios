import AVFoundation
import SwiftUI
import UIKit

@main
struct HarborApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Bigger image cache for posters.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
        // Play sound even when the silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

enum Orientation {
    @MainActor
    static func lock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)) { _ in }
            for window in scene.windows {
                var vc = window.rootViewController
                while let current = vc {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    vc = current.presentedViewController
                }
            }
        }
    }
}

enum Theme {
    static let background = Color(red: 0.035, green: 0.05, blue: 0.085)
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.10)
    static let accent = Color(red: 0.33, green: 0.72, blue: 0.98)
    static let dub = Color(red: 1.0, green: 0.62, blue: 0.22)
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView().harborDestinations() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { SearchView().harborDestinations() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView().harborDestinations() }
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

extension View {
    /// Registers the screens every tab can push to.
    func harborDestinations() -> some View {
        self
            .navigationDestination(for: MetaRoute.self) { route in
                MetaDetailView(route: route)
            }
            .navigationDestination(for: StreamRoute.self) { route in
                StreamsView(route: route)
            }
    }
}
