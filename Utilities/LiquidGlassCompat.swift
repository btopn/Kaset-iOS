import SwiftUI

// MARK: - Liquid Glass compatibility shim (iOS)

// Liquid Glass helpers. Kaset's macOS build gates these behind
// `#available(macOS 26.0, *)` with a macOS 15 fallback; this iOS port targets
// iOS 26.0+ where Liquid Glass is always available, so the helpers forward
// directly to Apple's APIs (`.glassEffect`, `GlassEffectContainer`,
// `.glassProminent`, etc.). The `usesLegacyMacOS15UI` environment value is
// retained as a no-op so ported views compile unchanged.

enum CompatGlassTransition {
    case materialize
}

extension View {
    func compatGlass(interactive: Bool = false, tint: Color? = nil, in shape: some Shape) -> some View {
        self.modifier(CompatGlassModifier(interactive: interactive, tint: tint, shape: shape))
    }

    func compatGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        self.modifier(CompatGlassIDModifier(id: id, namespace: namespace))
    }

    func compatGlassTransition(_ transition: CompatGlassTransition) -> some View {
        self.modifier(CompatGlassTransitionModifier(transition: transition))
    }

    /// Apply `.glassProminent` on iOS 26+.
    func compatGlassProminentButton() -> some View {
        self.modifier(CompatGlassProminentButtonModifier())
    }

    /// Gives a list/sidebar a translucent frosted appearance.
    /// On iOS 26 the floating Liquid Glass chrome is automatic, so this hides
    /// the list's opaque material to reveal it.
    func compatTranslucentSidebar() -> some View {
        self.scrollContentBackground(.hidden)
    }
}

// MARK: - CompatGlassModifier

private struct CompatGlassModifier<S: Shape>: ViewModifier {
    let interactive: Bool
    var tint: Color?
    let shape: S

    func body(content: Content) -> some View {
        content.glassEffect(self.glass, in: self.shape)
    }

    private var glass: Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if self.interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - CompatGlassIDModifier

private struct CompatGlassIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content.glassEffectID(self.id, in: self.namespace)
    }
}

// MARK: - CompatGlassTransitionModifier

private struct CompatGlassTransitionModifier: ViewModifier {
    let transition: CompatGlassTransition

    func body(content: Content) -> some View {
        switch self.transition {
        case .materialize:
            content.glassEffectTransition(.materialize)
        }
    }
}

// MARK: - CompatGlassProminentButtonModifier

private struct CompatGlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.glassProminent)
    }
}

// MARK: - CompatGlassContainer

struct CompatGlassContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: self.spacing) { self.content() }
    }
}
