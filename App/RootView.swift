import SwiftUI

/// Root view shown when the app launches. Placeholder until features are ported.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Kaset iOS",
            systemImage: "music.note",
            description: Text("Scaffolding ready. Porting services next.")
        )
    }
}

#Preview {
    RootView()
}
