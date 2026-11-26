import SwiftUI

@main
struct DearDiaryApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
    }
}

/// Start page → choose photos → draft → saved, all in one navigation stack.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .selection: SelectionView()
                    case .draft: DraftView()
                    case .saved: SavedView()
                    }
                }
        }
        .task { await state.loadDrafts() }
    }
}
