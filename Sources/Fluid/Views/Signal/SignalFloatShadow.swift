import AppKit
import Combine
import SwiftUI

/// The floating shadow under a Signal surface (DESIGN.md §6, "floating shadow", Atin 2026-09-29):
/// a soft, neutral shadow that lifts the pill, a recovery card or the history card off the screen.
///
/// It is drawn in a panel of its own, a child panel ordered just below the surface's panel, so it
/// moves with it while shown. Two reasons:
/// - Click-through. A transparent panel takes a click wherever its pixels are not clear, so a
///   shadow painted in the surface's own panel would turn its transparent margin into a click
///   trap. This panel ignores mouse events from creation and is never toggled.
/// - The window server's own shadow (`hasShadow`) was tried first: it rims every painted pixel with
///   a dark hairline, shadows the hover brackets and the chips too, and cannot be tuned per
///   appearance.
///
/// The panel mirrors the surface panel's alpha (so alpha 0 casts nothing, and a card's fade takes
/// its shadow with it) and its frame plus `margin`. The owner reports the surface's rect and wraps
/// the shadow in the surface's own visibility, so it never outlives or precedes the surface.
///
/// A surface on the dictation start path (the pill) sets `presentsWithParent: false` and calls
/// `present()` a main-queue turn after it is shown and `withdraw()` once hidden, so showing the
/// pill moves and orders one window, never two; the shadow may arrive a frame late.
@MainActor
final class SignalFloatShadow {
    @MainActor
    final class State: ObservableObject {
        /// The surface's rect in the surface panel's content, top-left origin. Nil draws nothing.
        @Published var surface: CGRect?
    }

    /// The shadow's panel. Parked offscreen with its surface, it is never clamped back onto a
    /// screen (a clamped child would land far from the pill on the next show).
    final class Panel: NSPanel {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }
    }

    static let margin = SignalTheme.Metrics.floatShadowMargin

    let state: State
    private let panel: Panel
    private let presentsWithParent: Bool
    private weak var parent: NSWindow?
    private var frameObservers: [NSObjectProtocol] = []
    private var alphaObservation: NSKeyValueObservation?
    /// Ordered under the parent as its child (or waiting for the parent to be ordered in).
    private(set) var isPresented = false

    init(presentsWithParent: Bool = true, @ViewBuilder root: (State) -> some View) {
        let state = State()
        let panel = Panel(
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
        self.presentsWithParent = presentsWithParent
    }

    /// Binds the shadow to `parent`: it follows its frame (plus the margin) and alpha, and, with
    /// `presentsWithParent`, is ordered under it as a child from now on. Idempotent.
    func attach(to parent: NSWindow) {
        if self.parent !== parent {
            self.detach()
            self.parent = parent
            self.frameObservers = [NSWindow.didResizeNotification, NSWindow.didMoveNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.parentFrameChanged() }
                }
            }
            // A child's alpha is its own: mirror the parent's, including each step of an animated
            // fade (AppKit sets a window's alpha step by step, and each step is observable). Hopped
            // to the next main-queue turn, so the parent's own alpha change never waits on it.
            self.alphaObservation = parent.observe(\.alphaValue, options: [.initial, .new]) { [weak self] window, _ in
                let alpha = window.alphaValue
                DispatchQueue.main.async { [weak self] in
                    self?.panel.alphaValue = alpha
                }
            }
        }
        if self.presentsWithParent {
            self.present()
        }
    }

    /// Orders the shadow under its parent as a child, fitted to it. Idempotent.
    func present() {
        guard let parent else { return }
        self.isPresented = true
        self.fitToParent()
        if self.panel.parent !== parent {
            parent.addChildWindow(self.panel, ordered: .below)
        }
    }

    /// Takes the shadow out: no longer a child, out of the window list, so the parent moves and
    /// orders alone (the pill's park, and its next show).
    func withdraw() {
        self.isPresented = false
        self.panel.parent?.removeChildWindow(self.panel)
        self.panel.orderOut(nil)
    }

    func detach() {
        self.frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
        self.frameObservers = []
        self.alphaObservation?.invalidate()
        self.alphaObservation = nil
        self.withdraw()
        self.parent = nil
    }

    /// The panel, for tests: its frame, alpha and click-through.
    var panelForTests: NSPanel {
        self.panel
    }

    /// The parent moved or resized. A presented child already moves with it; a clamp or a resize
    /// is corrected on the next main-queue turn, never inside the parent's own frame change. A
    /// withdrawn shadow is fitted when presented.
    private func parentFrameChanged() {
        guard self.isPresented else { return }
        if self.parent?.isVisible == true {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented else { return }
                self.fitToParent()
            }
        } else {
            self.fitToParent()
        }
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
                radius: self.palette.floatShadowRadius,
                x: 0,
                y: self.palette.floatShadowY,
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
