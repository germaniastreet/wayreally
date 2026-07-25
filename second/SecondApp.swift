import SwiftUI

@main
struct SecondApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // SecondTheme's colors are fixed RGB values, not adaptive
                // system colors, so the app was only ever designed for light
                // mode. Locking the scheme here prevents default-colored
                // text (e.g. transcript rows with no explicit foregroundStyle)
                // from silently flipping to white-on-white in system dark mode.
                .preferredColorScheme(.light)
        }
    }
}
