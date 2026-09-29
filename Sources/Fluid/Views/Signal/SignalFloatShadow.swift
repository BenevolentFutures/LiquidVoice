import AppKit
import Combine
import SwiftUI

/// The floating shadow under a Signal surface (DESIGN.md §6, "floating shadow", Atin 2026-09-29):
/// a soft, neutral shadow that lifts the pill, a recovery card or the history card off the screen.
///
/// It is drawn in a panel of its own, a child panel ordered just below the surface's panel, so it
/// moves with it. Two reasons:
/// - Click-through. A transparent panel takes a click wherever its pixels are not clear, so a
///   shadow painted in the surface's own panel would turn its transparent margin into a click
///   trap. This panel ignores mouse events from creation and is never toggled.
/// - The window server's own shadow (`hasShadow`) was tried first: it rims every painted pixel with
///   a dark hairline, shadows the hover brackets and the chips too, and cannot be tuned per
///   appearance.
///
/// The panel mirrors the surface panel's alpha (so alpha 0 casts nothing, and a card's fade takes
/// its shadow with it) and its size plus `margin`. The owner reports the surface's rect and wraps
/// the shadow in the surface's own visibility, so it never outlives or precedes the surface.
@MainActor
final class SignalFloatShadow {
    @MainActor
    final class State: ObservableObject {
        /// The surface's rect in the surface panel's content, top-left origin. Nil draws nothing.
        @Published var surface: CGRect?
    }

    static let margin = SignalTheme.Metrics.floatShadowMargin

    let state: State
    private let panel: NSPanel
    private weak var parent: NSWindow?
    private var resizeObserver: NSObjectProtocol?
    private var alphaObservation: NSKeyValueObservation?

    init(@ViewBuilder root: (State) -> some View) {
        let state = State()
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // Never takes a click. Set once here, never toggled: this panel only ever draws a shadow.
        panel.ignoresMouseEvents = true
        panel.setAccessibilityElement(false)
        let hostingView = NSHostingView(rootView: root(state).allowsHitTesting(false))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        self.state = state
        self.panel = panel
    }

    /// Puts the shadow under `parent`: a child panel ordered below it, sized to it plus the
    /// margin, following its moves (as a child), its resizes and its alpha. Idempotent.
    func attach(to parent: NSWindow) {
        if self.parent !== parent {
            self.detach()
            self.parent = parent
            self.resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.fitToParent() }
            }
            // A child's alpha is its own: mirror the parent's, including each step of an animated
            // fade (AppKit sets a window's alpha step by step, and each step is observable).
            self.alphaObservation = parent.observe(\.alphaValue, options: [.initial, .new]) { [weak self] window, _ in
                let alpha = window.alphaValue
                MainActor.assumeIsolated { self?.panel.alphaValue = alpha }
            }
        }
        self.fitToParent()
        if self.panel.parent !== parent {
            parent.addChildWindow(self.panel, ordered: .below)
        }
    }

    func detach() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        self.resizeObserver = nil
        self.alphaObservation?.invalidate()
        self.alphaObservation = nil
        self.panel.parent?.removeChildWindow(self.panel)
        self.panel.orderOut(nil)
        self.parent = nil
    }

    /// The panel, for tests: its frame, alpha and click-through.
    var panelForTests: NSPanel {
        self.panel
    }

    private func fitToParent() {
        guard let parent else { return }
        let frame = parent.frame.insetBy(dx: -Self.margin, dy: -Self.margin)
        if self.panel.frame != frame {
            self.panel.setFrame(frame, display: false)
        }
    }
}

/// The shadow alone: the surface's rect cast with the floating shadow, then the rect itself cleared,
/// so nothing is painted under the surface (a fading surface never shows a dark box through).
/// Laid out in the shadow panel, whose content is the surface panel's plus `margin` on every side.
struct SignalFloatShadowView: View {
    @ObservedObject var state: SignalFloatShadow.State
    var margin: CGFloat = SignalFloatShadow.margin

    @Environment(\.signalPalette) private var palette

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            guard let surface = self.state.surface, surface.width > 0, surface.height > 0 else { return }
            let rect = Path(surface.offsetBy(dx: self.margin, dy: self.margin))
            var shadow = context
            shadow.addFilter(.shadow(
                color: self.palette.floatShadow,
                radius: SignalTheme.Metrics.floatShadowRadius,
                x: 0,
                y: SignalTheme.Metrics.floatShadowY,
                options: .shadowOnly
            ))
            shadow.fill(rect, with: .color(.black))
            context.blendMode = .clear
            context.fill(rect, with: .color(.black))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Reports this surface's rect (in its panel's content, top-left origin) to its floating shadow.
    func signalFloatShadowSource(_ state: SignalFloatShadow.State?) -> some View {
        self.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            guard let state, state.surface != frame else { return }
            state.surface = frame
        }
    }
}
