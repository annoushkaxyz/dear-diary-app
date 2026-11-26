import SwiftUI

/// Every saved draft, compact: a few photos, the first line, and when it was last touched.
struct DraftsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let onOpen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.drafts) { draft in
                    Button {
                        Haptics.tap()
                        onOpen(draft.id)
                    } label: {
                        DraftRow(draft: draft, isOpen: draft.id == state.currentDraftID)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.hairline)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
                .onDelete { offsets in
                    Haptics.bump(.medium)
                    let ids = offsets.map { state.drafts[$0].id }
                    for id in ids { state.deleteDraft(id) }
                    if state.drafts.isEmpty { dismiss() }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}

private struct DraftRow: View {
    let draft: DraftStore.Summary
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 14) {
            // The first few photos, overlapping like a small stack of pages.
            HStack(spacing: -22) {
                ForEach(0..<max(1, min(draft.thumbs.count, 3)), id: \.self) { i in
                    Group {
                        if draft.thumbs.indices.contains(i) {
                            Image(uiImage: draft.thumbs[i])
                                .resizable()
                                .scaledToFill()
                        } else {
                            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                        .frame(width: 42, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.background, lineWidth: 1.5))
                        .rotationEffect(.degrees(Double(i) * 4))
                        .zIndex(Double(3 - i))
                }
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(draft.photoCount) photos · \(draft.date.formatted(.relative(presentation: .named)))")
                        .font(Theme.font(12, .regular))
                        .foregroundStyle(Theme.muted)
                    if draft.exported {
                        Text("Saved")
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .glassEffect(.regular, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
            if isOpen {
                Circle().fill(Theme.ink).frame(width: 6, height: 6)
                    .accessibilityLabel("Open now")
            }
        }
        .contentShape(Rectangle())
    }
}
