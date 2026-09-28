import AppKit
import QuartzCore
import SwiftUI

/// The voice trace and its age ruler in one Canvas (DESIGN.md §4, §11): square-ended ink bars
/// mirrored about a 1 px midline, the newest six in orange while live, four printed opacity
/// steps by age, and static ruler ticks below (2 pt every 0.25 s, 4 pt every 1 s) in a 6 pt band
/// that stays reserved. The transcribing sweep is a Core Animation layer, so it costs the main
/// thread nothing while the final pass runs.
struct SignalTraceView: View {
    let model: SignalTraceModel
    /// Recording: the frame clock runs and the write head is orange.
    let isLive: Bool
    /// Transcribing: the orange 24 x 4 block steps across on the bar pitch.
    let isSweeping: Bool
    var showsAgeRuler = true

    @Environment(\.signalPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Keeps the frame clock running briefly after a stop, for the 60 ms stop-to-flat.
    @State private var settlesUntil: Date = .distantPast

    private var width: CGFloat {
        SignalTraceModel.width(forBars: self.model.barCount)
    }

    private var height: CGFloat {
        SignalTheme.Metrics.traceHeight + SignalTheme.Metrics.rulerHeight
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !self.isLive && Date() >= self.settlesUntil)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                let now = timeline.date.timeIntervalSinceReferenceDate
                self.model.reducesMotion = self.reduceMotion
                self.model.advance(to: now)
                self.draw(in: &context, now: now)
            }
        }
        .frame(width: self.width, height: self.height)
        .overlay(alignment: .topLeading) {
            if self.isSweeping {
                SignalSweep(traceWidth: self.width, reducesMotion: self.reduceMotion)
                    .frame(width: self.width, height: SignalTheme.Metrics.traceHeight)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: self.isLive) { _, live in
            guard !live else { return }
            let settle = SignalTheme.Motion.stopToFlat + 0.04
            self.settlesUntil = Date().addingTimeInterval(settle)
            DispatchQueue.main.asyncAfter(deadline: .now() + settle + 0.02) {
                self.settlesUntil = .distantPast
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, now: TimeInterval) {
        let metrics = SignalTheme.Metrics.self
        let mid = metrics.traceMidline
        // The 1 px midline rule, full width, behind the bars.
        context.fill(Path(CGRect(x: 0, y: mid - 0.5, width: self.width, height: 1)), with: .color(self.palette.midline))

        let count = self.model.barCount
        let live = self.model.isLive
        for index in 0..<count {
            let age = count - 1 - index
            let barHeight = self.model.shownHeight(at: index, now: now)
            let x = self.width - metrics.barWidth - CGFloat(age) * metrics.barPitch
            let isHead = live && age < metrics.writeHeadBars
            let color = isHead
                ? self.palette.accent
                : self.palette.ink.opacity(SignalTraceModel.bandOpacity(age: age))
            context.fill(
                Path(CGRect(x: x, y: mid - barHeight / 2, width: metrics.barWidth, height: barHeight)),
                with: .color(color)
            )
        }

        guard self.showsAgeRuler else { return }
        // Static: a tick at each bar's centre, every 3 bars (0.25 s), taller every 12 (1 s).
        let samplesPerSecond = Int(metrics.samplesPerSecond)
        for age in stride(from: 0, to: count, by: 3) {
            let x = self.width - metrics.barWidth / 2 - 0.5 - CGFloat(age) * metrics.barPitch
            let tick: CGFloat = age % samplesPerSecond == 0 ? 4 : 2
            context.fill(
                Path(CGRect(x: x, y: metrics.traceHeight + 1, width: 1, height: tick)),
                with: .color(self.palette.graticule)
            )
        }
    }
}

/// The transcribing sweep: a solid 24 x 4 orange block stepped across the trace on the 4 pt
/// pitch every 1.05 s, as a discrete keyframe animation the compositor runs. Reduced motion holds
/// four positions per cycle.
private struct SignalSweep: NSViewRepresentable {
    let traceWidth: CGFloat
    let reducesMotion: Bool

    func makeNSView(context: Context) -> SignalSweepView {
        SignalSweepView()
    }

    func updateNSView(_ view: SignalSweepView, context: Context) {
        view.configure(traceWidth: self.traceWidth, reducesMotion: self.reducesMotion)
    }
}

final class SignalSweepView: NSView {
    private let block = CALayer()
    private var traceWidth: CGFloat = 0
    private var reducesMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.block.backgroundColor = SignalTheme.AppKitColors.accent.cgColor
        self.block.anchorPoint = .zero
        self.block.actions = ["position": NSNull(), "bounds": NSNull()]
        self.layer?.addSublayer(self.block)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func configure(traceWidth: CGFloat, reducesMotion: Bool) {
        let changed = traceWidth != self.traceWidth || reducesMotion != self.reducesMotion
        self.traceWidth = traceWidth
        self.reducesMotion = reducesMotion
        if changed { self.restart() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.restart()
    }

    override func layout() {
        super.layout()
        self.restart()
    }

    private func restart() {
        let metrics = SignalTheme.Metrics.self
        self.block.removeAllAnimations()
        guard self.window != nil, self.traceWidth > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Layer geometry of a flipped view is flipped too: y runs down from the trace's top.
        let top = metrics.traceMidline - metrics.sweepHeight / 2
        self.block.frame = CGRect(x: -metrics.sweepWidth, y: top, width: metrics.sweepWidth, height: metrics.sweepHeight)
        CATransaction.commit()

        let steps = Self.steps(traceWidth: self.traceWidth, reducesMotion: self.reducesMotion)
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = steps.map { $0.x }
        // Discrete keyframes take one more key time than values, ending at 1.
        animation.keyTimes = steps.map { NSNumber(value: $0.time) } + [1]
        animation.calculationMode = .discrete
        animation.duration = SignalTheme.Motion.sweepPeriod
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        self.block.add(animation, forKey: "signal.sweep")
    }

    /// The block's left edge and when it moves there, as fractions of the period: the prototype's
    /// `x = 1 + round((-24 + p * (width + 24)) / 4) * 4`, one keyframe per step.
    static func steps(traceWidth: CGFloat, reducesMotion: Bool) -> [(x: CGFloat, time: Double)] {
        let metrics = SignalTheme.Metrics.self
        let span = traceWidth + metrics.sweepWidth
        func x(at progress: Double) -> CGFloat {
            1 + ((-metrics.sweepWidth + CGFloat(progress) * span) / metrics.barPitch).rounded() * metrics.barPitch
        }
        if reducesMotion {
            return (0..<4).map { quarter in
                let time = Double(quarter) / 4
                return (x(at: time + 0.125), time)
            }
        }
        var steps: [(x: CGFloat, time: Double)] = [(x(at: 0), 0)]
        let resolution = 2000
        for tick in 1..<resolution {
            let time = Double(tick) / Double(resolution)
            let position = x(at: time)
            if position != steps[steps.count - 1].x {
                steps.append((position, time))
            }
        }
        return steps
    }
}
