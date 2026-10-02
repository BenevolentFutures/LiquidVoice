import AppKit

/// The menu bar mark (DESIGN.md §10): a 22 x 16 square-cornered template image. Three
/// square-ended bars at rest; bars plus a solid square while listening (the bars follow the level
/// at 8 Hz, still during Spoken Send's countdown); bars plus an outlined square while
/// transcribing. The width never changes. On hover, and while the menu is open, a bracket draws
/// inside the box (the menu bar has no room outside it).
enum SignalMenuBarMark {
    enum Kind: Equatable {
        case idle
        case listening
        case transcribing
    }

    static let size = NSSize(width: 22, height: 16)
    /// The bars' heights at rest.
    static let restingBars: [CGFloat] = [6, 10, 7]

    private static var cache: [String: NSImage] = [:]

    static func image(kind: Kind, bars: [CGFloat] = restingBars, bracket: Bool) -> NSImage {
        let key = "\(kind)|\(bars.map { String(Int($0)) }.joined(separator: ","))|\(bracket)"
        if let cached = self.cache[key] { return cached }
        let image = NSImage(size: self.size, flipped: true) { _ in
            NSColor.black.set()
            // Bars: 2 pt wide on a 3 pt pitch from x 4, centred on y 8, square-ended.
            for (index, height) in bars.prefix(3).enumerated() {
                let rect = NSRect(x: 4 + CGFloat(index) * 3, y: 8 - height / 2, width: 2, height: height)
                NSBezierPath(rect: rect).fill()
            }
            switch kind {
            case .idle:
                break
            case .listening:
                NSBezierPath(rect: NSRect(x: 14, y: 5, width: 6, height: 6)).fill()
            case .transcribing:
                let outline = NSBezierPath(rect: NSRect(x: 14.75, y: 5.75, width: 4.5, height: 4.5))
                outline.lineWidth = 1.5
                outline.stroke()
            }
            if bracket {
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .butt
                path.lineJoinStyle = .miter
                let corners: [[NSPoint]] = [
                    [NSPoint(x: 0.75, y: 4.75), NSPoint(x: 0.75, y: 0.75), NSPoint(x: 4.75, y: 0.75)],
                    [NSPoint(x: 17.25, y: 0.75), NSPoint(x: 21.25, y: 0.75), NSPoint(x: 21.25, y: 4.75)],
                    [NSPoint(x: 21.25, y: 11.25), NSPoint(x: 21.25, y: 15.25), NSPoint(x: 17.25, y: 15.25)],
                    [NSPoint(x: 4.75, y: 15.25), NSPoint(x: 0.75, y: 15.25), NSPoint(x: 0.75, y: 11.25)],
                ]
                for corner in corners {
                    path.move(to: corner[0])
                    path.line(to: corner[1])
                    path.line(to: corner[2])
                }
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MouthKeys"
        if self.cache.count > 256 { self.cache.removeAll() }
        self.cache[key] = image
        return image
    }

    /// Three recent trace samples as the listening bars, in 2 pt steps. The floor keeps the
    /// mark's own silhouette in silence (never three dots, which would read as an overflow "…").
    /// The pill's trace holds its last words still in silence; the mark does not: once the voice
    /// has been off past the 250 ms hangover it rests on the floor, so it never looks loud while
    /// Atin is quiet.
    static func listeningBars(
        from trace: SignalTraceModel,
        at now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> [CGFloat] {
        let floor: [CGFloat] = [4, 6, 4]
        let cap: [CGFloat] = [10, 12, 10]
        let ages = [4, 1, 7]
        guard trace.isVoiceActive(at: now) else { return floor }
        let count = trace.current.count
        return ages.enumerated().map { index, age in
            guard count > age else { return floor[index] }
            let sample = trace.current[count - 1 - age]
            let level = (sample - SignalTraceModel.floor) / (SignalTraceModel.ceiling - SignalTraceModel.floor)
            return min(cap[index], floor[index] + 2 * (level * 3).rounded())
        }
    }
}

/// The menu's header row: "MOUTHKEYS" on the left and the state on the right, mono 10 pt
/// uppercase, with the orange square while listening (DESIGN.md §10).
final class SignalMenuHeaderView: NSView {
    var stateText = "Ready" {
        didSet { if self.stateText != oldValue { self.needsDisplay = true } }
    }

    var isLive = false {
        didSet { if self.isLive != oldValue { self.needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 262, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 14
        let label = self.attributed("MouthKeys", weight: .medium, color: .secondaryLabelColor)
        let labelSize = label.size()
        label.draw(at: NSPoint(x: inset, y: (self.bounds.height - labelSize.height) / 2))

        let state = self.attributed(self.stateText, weight: .semibold, color: .labelColor)
        let stateSize = state.size()
        let stateX = self.bounds.width - inset - stateSize.width
        state.draw(at: NSPoint(x: stateX, y: (self.bounds.height - stateSize.height) / 2))
        if self.isLive {
            SignalTheme.AppKitColors.accent.setFill()
            NSRect(x: stateX - 12, y: self.bounds.midY - 3, width: 6, height: 6).fill()
        }
    }

    private func attributed(_ text: String, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: weight),
            .kern: 0.6,
            .foregroundColor: color,
        ])
    }
}
