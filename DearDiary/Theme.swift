import SwiftUI
import UIKit

/// A quiet, dark, photo-first look: SF Pro Medium in lowercase, like the posts themselves.
enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.05)
    static let surface = Color.white.opacity(0.07)
    static let surfaceStrong = Color.white.opacity(0.14)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.3)
    static let hairline = Color.white.opacity(0.12)
    static let buttonHeight: CGFloat = 54
    /// Corner radius for photo cards.
    static let cardRadius: CGFloat = 20

    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Liquid Glass pill: white-tinted glass (primary) or clear glass (secondary).
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .foregroundStyle(prominent ? Color.black : Theme.ink)
            .contentShape(Capsule())
            // No interactive bounce on big buttons: they just dim slightly while pressed.
            .glassEffect(prominent ? .regular.tint(.white) : .regular, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// Round icon button. Use `size: Theme.buttonHeight` next to a pill so they match.
struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(size > 50 ? 18 : 15))
            .frame(width: size, height: size)
            .foregroundStyle(Theme.ink)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .opacity(isEnabled ? 1 : 0.3)
    }
}

/// Selectable capsule, e.g. "today · since yesterday · last 7 days".
struct Chip: View {
    let title: String
    let selected: Bool
    /// Stretch to share the row's full width with the other chips.
    var fill = false
    let action: () -> Void

    init(title: String, selected: Bool, fill: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.fill = fill
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(14))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, fill ? 10 : 14)
                .frame(maxWidth: fill ? .infinity : nil)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? Color.black : Theme.ink)
                .glassEffect(selected ? .regular.tint(.white).interactive() : .regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Solid bar background that fades into the content scrolling underneath.
struct BottomBarBackground: View {
    var body: some View {
        Theme.background
            .overlay(alignment: .top) {
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 32)
                    .offset(y: -32)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}

extension String {
    /// First letter capitalised, the rest untouched (for UI text, never for captions).
    var sentenceCased: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Small grey label above a group of controls.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.font(12))
            .foregroundStyle(Theme.muted)
    }
}

/// Replaces the system back button with a plain one. The system one also lets a sideways swipe
/// anywhere on the screen go back, which is too easy to do by accident while swiping photos.
private struct BackButtonOnly: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if !state.path.isEmpty { state.path.removeLast() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Back")
                }
            }
    }
}

extension View {
    /// Back only by tapping the back button, never by swiping.
    func backButtonOnly() -> some View { modifier(BackButtonOnly()) }
}

/// Small taps of the Taptic Engine, used across the app.
enum Haptics {
    /// Choosing between options (a caption, a position, a photo).
    static func tap() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Something moved or arrived.
    static func bump(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
