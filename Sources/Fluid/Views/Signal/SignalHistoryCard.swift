import AppKit
import SwiftUI

/// The history card (DESIGN.md §4, §9.6): an engineering table, 480 wide and at most 480 tall,
/// square with a 1 px edge and the drop rule. A mono index column ("01" over the time), day rows,
/// 1 px rules, transcripts clamped to 4 lines, mono meta with the orange NOT PASTED marker, and a
/// title-block footer. Rows invert on hover; a click inserts.
struct SignalHistoryCard: View {
    let entries: [TranscriptionHistoryEntry]
    let totalCount: Int
    /// Transcripts whose paste failed this session (NOT PASTED).
    let notPasted: Set<String>
    var now = Date()
    /// Holds a row inverted for renders and inspection (the prototype's `?hoverRow=`), 1-based.
    var inspectionHoverRow: Int?
    /// Renders (ImageRenderer draws no scroll view): the rows clipped to the list's height instead.
    var isStatic = false
    let onPick: (TranscriptionHistoryEntry) -> Void
    var onHoverChanged: (Bool) -> Void = { _ in }

    @Environment(\.signalPalette) private var palette
    @State private var hoveredRowID: UUID?
    @State private var isHovered = false

    private var metrics: SignalTheme.Metrics.Type {
        SignalTheme.Metrics.self
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.list
            self.footer
        }
        .frame(width: self.metrics.historyWidth - 2)
        .padding(1)
        .signalSurface()
        // No bracket on the card as a whole: it is not clickable; its rows invert on hover
        // (DESIGN.md §7, Atin 2026-09-29).
        .onHover { hovering in
            self.isHovered = hovering
            self.onHoverChanged(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent dictations")
    }

    // MARK: Header and footer

    private var header: some View {
        HStack {
            self.label("Recent dictations", color: self.palette.text, weight: .semibold)
            Spacer(minLength: 8)
            self.label("Click to insert", color: self.palette.text2)
        }
        .padding(.horizontal, self.metrics.historyPaddingHorizontal)
        .frame(height: self.metrics.historyHeader)
        .overlay(alignment: .bottom) { self.rule }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            self.label(
                "History · \(self.entries.count) of \(self.totalCount) · Newest first",
                color: self.palette.text2
            )
            .padding(.horizontal, self.metrics.historyPaddingHorizontal)
            .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
            self.label("Liquid Voice", color: self.palette.text, weight: .semibold)
                .padding(.horizontal, self.metrics.historyPaddingHorizontal)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { self.verticalRule }
        }
        .frame(height: self.metrics.historyFooter)
        .overlay(alignment: .top) { self.rule }
    }

    private func label(_ text: String, color: Color, weight: Font.Weight = .medium) -> some View {
        let role = SignalTheme.Typography.tableLabel
        return Text(text)
            .font(.system(size: role.size, weight: weight, design: .monospaced))
            .tracking(role.tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var rule: some View {
        Rectangle().fill(self.palette.rule).frame(height: 1)
    }

    private var verticalRule: some View {
        Rectangle().fill(self.palette.rule).frame(width: 1)
    }

    // MARK: List

    /// Header, footer and the edge leave this much of the 480 for the list.
    /// The 480 pt card less its 1 px border, header and footer.
    private var maxListHeight: CGFloat {
        self.metrics.historyMaxHeight - 2 * SignalTheme.Metrics.edgeWidth - self.metrics.historyHeader - self.metrics.historyFooter
    }

    @ViewBuilder
    private var list: some View {
        if self.isStatic {
            self.rows
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: self.maxListHeight, alignment: .top)
                .clipped()
        } else {
            self.scrollingList
        }
    }

    /// The list scrolls past 480 - header - footer; below that it takes its rows' height, which
    /// the panel reads through its hosting view's fitting size (as the card always did).
    private var scrollingList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            self.rows
        }
        .frame(maxHeight: self.maxListHeight)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if self.entries.isEmpty {
                Text("No dictations yet")
                    .font(SignalTheme.Typography.historyTranscript.font)
                    .foregroundStyle(self.palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, self.metrics.historyPaddingHorizontal)
                    .frame(height: 44)
            }
            ForEach(Array(self.dayGroups.enumerated()), id: \.offset) { groupIndex, group in
                self.dayRow(group.title, isFirst: groupIndex == 0)
                ForEach(group.items, id: \.entry.id) { item in
                    self.entryRow(item.entry, index: item.index)
                }
            }
        }
    }

    private struct Item {
        let entry: TranscriptionHistoryEntry
        let index: Int
    }

    private var dayGroups: [(title: String, items: [Item])] {
        var groups: [(title: String, items: [Item])] = []
        for (offset, entry) in self.entries.enumerated() {
            let title = Self.dayTitle(entry.timestamp, now: self.now)
            if groups.last?.title == title {
                groups[groups.count - 1].items.append(Item(entry: entry, index: offset + 1))
            } else {
                groups.append((title, [Item(entry: entry, index: offset + 1)]))
            }
        }
        return groups
    }

    private func dayRow(_ title: String, isFirst: Bool) -> some View {
        self.label(title, color: self.palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, self.metrics.historyPaddingHorizontal)
            .frame(height: self.metrics.historyDayRow)
            .overlay(alignment: .top) {
                if !isFirst { self.rule }
            }
    }

    private func entryRow(_ entry: TranscriptionHistoryEntry, index: Int) -> some View {
        let isHovered = self.hoveredRowID == entry.id || self.inspectionHoverRow == index
        let primary = isHovered ? self.palette.invForeground : self.palette.text
        let secondary = isHovered ? self.palette.invForeground2 : self.palette.text2
        let text = Self.displayText(entry)
        let transcript = SignalTheme.Typography.historyTranscript
        return Button {
            self.onPick(entry)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "%02d", index))
                        .font(SignalTheme.Typography.historyIndex.font)
                        .frame(height: SignalTheme.Typography.historyIndex.lineHeight)
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(SignalTheme.Typography.historyTime.font)
                        .tracking(SignalTheme.Typography.historyTime.tracking)
                        .frame(height: SignalTheme.Typography.historyTime.lineHeight)
                }
                .foregroundStyle(secondary)
                .lineLimit(1)
                .frame(width: self.metrics.historyIndexColumn, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .signalType(transcript)
                        .foregroundStyle(primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, transcript.lineSpacing / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        SignalMonoLabel(text: Self.meta(entry), color: secondary)
                        if self.notPasted.contains(text) {
                            HStack(spacing: 6) {
                                Rectangle().fill(self.palette.accent).frame(width: 6, height: 6)
                                Text("Not pasted")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .tracking(0.63)
                                    .textCase(.uppercase)
                                    .foregroundStyle(primary)
                            }
                            .padding(.leading, 12)
                        }
                    }
                    .frame(height: 15)
                }
            }
            .padding(.top, 11)
            .padding(.bottom, 12)
            .padding(.horizontal, self.metrics.historyPaddingHorizontal)
            .background(isHovered ? self.palette.invBackground : Color.clear)
            .overlay(alignment: .top) { self.rule }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                self.hoveredRowID = entry.id
            } else if self.hoveredRowID == entry.id {
                self.hoveredRowID = nil
            }
        }
        .help("Insert this dictation into the focused app")
    }

    // MARK: Text

    static func displayText(_ entry: TranscriptionHistoryEntry) -> String {
        let processed = entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return processed.isEmpty ? entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines) : processed
    }

    /// "0:41 · 118 WORDS · C11": the duration when the audio was kept, the words, the app.
    static func meta(_ entry: TranscriptionHistoryEntry) -> String {
        var parts: [String] = []
        if let milliseconds = entry.audio?.durationMilliseconds {
            parts.append(SignalOverlayModel.formatDuration(Double(milliseconds) / 1000))
        }
        let words = SignalOverlayModel.wordCount(self.displayText(entry))
        parts.append("\(words) \(words == 1 ? "word" : "words")")
        let app = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !app.isEmpty { parts.append(app) }
        return parts.joined(separator: " · ")
    }

    /// "Today · Sep 28", "Yesterday · Sep 27", else the weekday ("Friday · Sep 26").
    static func dayTitle(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = self.weekdayFormatter.string(from: date)
        }
        return "\(day) · \(self.dateFormatter.string(from: date))"
    }

    /// "3:04 PM", or "15:04" when the system clock is set to 24-hour time.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
