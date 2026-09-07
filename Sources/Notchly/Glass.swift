import AppKit
import SwiftUI

// MARK: - Glass material backing

/// Native material behind the themed glass shape: NSGlassEffectView on
/// macOS 26, hudWindow vibrancy otherwise, or a solid tinted panel.
struct GlassMaterialView: NSViewRepresentable {
    let tint: Color

    func makeNSView(context: Context) -> NSView {
        let style = AppearanceSettings.windowStyle
        if #available(macOS 26.0, *), style == .liquidGlass {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.tintColor = NSColor(tint).withAlphaComponent(0.14)
            return glass
        }
        if style == .solid {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor(AppearanceSettings.theme.solidColor).cgColor
            return solid
        }
        let translucent = NSVisualEffectView()
        translucent.material = .hudWindow
        translucent.blendingMode = .behindWindow
        translucent.state = .active
        translucent.wantsLayer = true
        translucent.layer?.backgroundColor = NSColor(tint).withAlphaComponent(0.14).cgColor
        return translucent
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let style = AppearanceSettings.windowStyle
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.tintColor = NSColor(tint).withAlphaComponent(0.14)
        } else if let translucent = nsView as? NSVisualEffectView {
            translucent.layer?.backgroundColor = NSColor(tint).withAlphaComponent(0.14).cgColor
        } else if let solid = nsView as? NSView, style == .solid {
            solid.layer?.backgroundColor = NSColor(AppearanceSettings.theme.solidColor).cgColor
        }
    }
}

// MARK: - Themed glass shape

/// Any shape rendered as themed glass: native liquid glass on macOS 26,
/// vibrancy fallback elsewhere, plus a subtle reflection sweep and hairline.
struct ThemedGlass<S: Shape>: View {
    let shape: S

    private var tint: Color { AppearanceSettings.theme.color }

    var body: some View {
        // Dark underlay guarantees contrast on any wallpaper; the material and
        // reflection keep the glass look on top of it.
        let base = shape
            .fill(Color.black.opacity(0.45))
            .background(GlassMaterialView(tint: tint))
            .clipShape(shape)
            .overlay(glassReflection)
            .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.8))

        if #available(macOS 26.0, *), AppearanceSettings.windowStyle == .liquidGlass {
            shape
                .fill(Color.black.opacity(0.38))
                .glassEffect(
                    .regular
                        .tint(tint.opacity(0.14))
                        .interactive(),
                    in: shape
                )
                .overlay(glassReflection)
                .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        } else {
            base
        }
    }

    private var glassReflection: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.white.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
