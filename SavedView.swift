import SwiftUI

/// After saving: the finished entry, with a way into Photos or straight into a new entry.
struct SavedView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.58, max(geo.size.height - 220, 200) * 0.75)
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(state.savedImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: cardWidth * CaptionSpec.aspect)
                                .clipShape(Rectangle()) // square, exactly like the saved image
                                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content.scaleEffect(phase.isIdentity ? 1 : 0.88)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .frame(height: cardWidth * CaptionSpec.aspect)

                VStack(spacing: 6) {
                    Text("Saved to camera roll")
                        .font(Theme.font(24))
                        .foregroundStyle(Theme.ink)
                    Text("\(state.savedImages.count) photos, in order")
                        .font(Theme.font(15, .regular))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .backButtonOnly()
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: "photos-redirect://") { openURL(url) }
                } label: {
                    Label("Open Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    Haptics.bump()
                    state.startNewEntry()
                } label: {
                    Text("New entry")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}
