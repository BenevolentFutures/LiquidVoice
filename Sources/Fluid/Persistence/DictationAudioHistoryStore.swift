import Foundation

struct DictationAudioSnapshot: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channels: Int

    var durationMilliseconds: Int {
        guard self.sampleRate > 0, self.channels > 0 else { return 0 }
        let frames = Double(self.samples.count) / Double(self.channels)
        return Int((frames / Double(self.sampleRate) * 1000).rounded())
    }
}

nonisolated struct DictationAudioMetadata: Codable, Equatable, Sendable {
    let fileName: String
    let durationMilliseconds: Int
    let byteCount: Int
    let sampleRate: Int
    let channels: Int
    let model: String?
}

enum DictationAudioHistoryError: LocalizedError {
    case applicationSupportUnavailable
    case audioMissing
    case noAudioEntries
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Could not access Application Support."
        case .audioMissing:
            return "Saved audio is missing."
        case .noAudioEntries:
            return "No saved dictation audio is available to export."
        case let .zipFailed(message):
            return "Could not create export zip. \(message)"
        }
    }
}

final nonisolated class DictationAudioHistoryStore: @unchecked Sendable {
    static let shared = DictationAudioHistoryStore()

    private let appSupportFolder = AppStorageLocation.folderName
    private let audioFolder = "DictationAudioHistory"
    private let fileManager = FileManager.default
    /// Replaces `~/Library/Application Support/<app folder>` (tests use a temporary directory).
    private let rootDirectoryOverride: URL?

    /// Posted on the main queue when the user's "Clear all history" or "Delete all saved audio"
    /// discards the kept recording too, so ASRService forgets its copy.
    static let keptDictationDiscardedNotification = Notification.Name("LiquidVoice.keptDictationDiscarded")

    init(rootDirectoryOverride: URL? = nil) {
        self.rootDirectoryOverride = rootDirectoryOverride
    }

    /// The app's storage folder (or the test override).
    private func rootDirectory() throws -> URL {
        if let rootDirectoryOverride = self.rootDirectoryOverride { return rootDirectoryOverride }
        guard let base = self.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DictationAudioHistoryError.applicationSupportUnavailable
        }
        return base.appendingPathComponent(self.appSupportFolder, isDirectory: true)
    }

    func save(
        snapshot: DictationAudioSnapshot,
        entryID: UUID,
        timestamp: Date,
        model: String?
    ) throws -> DictationAudioMetadata {
        let directory = try self.audioDirectory()
        let fileName = self.audioFileName(entryID: entryID, timestamp: timestamp)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        let data = Self.wavData(from: snapshot)
        try data.write(to: url, options: .atomic)

        return DictationAudioMetadata(
            fileName: fileName,
            durationMilliseconds: snapshot.durationMilliseconds,
            byteCount: data.count,
            sampleRate: snapshot.sampleRate,
            channels: snapshot.channels,
            model: model
        )
    }

    func audioFileURL(for entry: TranscriptionHistoryEntry) -> URL? {
        guard let audio = entry.audio else { return nil }
        return self.audioFileURL(fileName: audio.fileName, createIfNeeded: false)
    }

    func audioFileExists(for entry: TranscriptionHistoryEntry) -> Bool {
        guard let url = self.audioFileURL(for: entry) else { return false }
        return self.fileManager.fileExists(atPath: url.path)
    }

    @discardableResult
    func deleteAudio(fileName: String) -> Int64 {
        guard let url = self.audioFileURL(fileName: fileName, createIfNeeded: false) else {
            return 0
        }

        return self.deleteAudioFile(at: url) ?? 0
    }

    func deleteUnreferencedAudioFiles(referencedFileNames: Set<String>) -> (fileCount: Int, byteCount: Int64) {
        guard let directory = try? self.audioDirectory(createIfNeeded: false),
              self.fileManager.fileExists(atPath: directory.path)
        else {
            return (0, 0)
        }

        let files = (try? self.fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var fileCount = 0
        var byteCount: Int64 = 0
        for file in files where file.pathExtension.lowercased() == "wav" && !referencedFileNames.contains(file.lastPathComponent) {
            guard let removedBytes = self.deleteAudioFile(at: file) else { continue }
            fileCount += 1
            byteCount += removedBytes
        }

        return (fileCount, byteCount)
    }

    private func deleteAudioFile(at url: URL) -> Int64? {
        guard self.fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        do {
            try self.fileManager.removeItem(at: url)
            return fileSize
        } catch {
            return nil
        }
    }

    func deleteAllAudioFiles() {
        guard let directory = try? self.audioDirectory(createIfNeeded: false),
              self.fileManager.fileExists(atPath: directory.path)
        else {
            return
        }
        let files = (try? self.fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "wav" {
            try? self.fileManager.removeItem(at: file)
        }
    }

    func audioUsageBytes() -> Int64 {
        guard let directory = try? self.audioDirectory(createIfNeeded: false),
              let files = try? self.fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.fileSizeKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return 0
        }

        return files.reduce(Int64(0)) { total, url in
            guard url.pathExtension.lowercased() == "wav",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize
            else {
                return total
            }
            return total + Int64(size)
        }
    }

    func exportAudioArchive(entries: [TranscriptionHistoryEntry], to destinationURL: URL) throws {
        try self.exportArchive(entries: entries, to: destinationURL)
    }

    func exportPair(entry: TranscriptionHistoryEntry, to destinationURL: URL) throws {
        try self.exportArchive(entries: [entry], to: destinationURL)
    }

    func suggestedAudioExportFilename(for date: Date = Date()) -> String {
        "MouthKeys_Audio_\(Self.fileTimestampFormatter.string(from: date)).zip"
    }

    func suggestedPairExportFilename(for entry: TranscriptionHistoryEntry) -> String {
        "MouthKeys_Pair_\(Self.fileTimestampFormatter.string(from: entry.timestamp))_\(entry.id.uuidString.prefix(8)).zip"
    }

    static func formattedGigabytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb < 0.1 {
            return String(format: "%.2f GB", gb)
        }
        return String(format: "%.1f GB", gb)
    }

    static func bytes(forGigabytes gigabytes: Double) -> Int64 {
        Int64((gigabytes * 1_073_741_824.0).rounded())
    }

    private func exportArchive(entries: [TranscriptionHistoryEntry], to destinationURL: URL) throws {
        let exportEntries = entries.filter { self.audioFileExists(for: $0) }
        guard !exportEntries.isEmpty else { throw DictationAudioHistoryError.noAudioEntries }

        let staging = self.fileManager.temporaryDirectory
            .appendingPathComponent("fluidvoice-audio-\(UUID().uuidString)", isDirectory: true)
        let audioDirectory = staging.appendingPathComponent("audio", isDirectory: true)

        try self.fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? self.fileManager.removeItem(at: staging) }

        var manifestLines: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for entry in exportEntries.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let sourceURL = self.audioFileURL(for: entry),
                  let audio = entry.audio
            else {
                continue
            }

            let exportFileName = "\(Self.fileTimestampFormatter.string(from: entry.timestamp))_\(entry.id.uuidString.prefix(8)).wav"
            let relativeAudioPath = "audio/\(exportFileName)"
            try self.fileManager.copyItem(
                at: sourceURL,
                to: audioDirectory.appendingPathComponent(exportFileName, isDirectory: false)
            )

            let row = AudioManifestRow(
                audio: relativeAudioPath,
                text: entry.rawText,
                rawTranscript: entry.rawText,
                finalTranscript: entry.processedText,
                timestamp: Self.isoFormatter.string(from: entry.timestamp),
                durationMilliseconds: audio.durationMilliseconds,
                sampleRate: audio.sampleRate,
                channels: audio.channels,
                app: entry.appName,
                model: audio.model ?? ""
            )
            let data = try encoder.encode(row)
            if let line = String(data: data, encoding: .utf8) {
                manifestLines.append(line)
            }
        }

        guard !manifestLines.isEmpty else { throw DictationAudioHistoryError.noAudioEntries }
        let manifestURL = staging.appendingPathComponent("manifest.jsonl", isDirectory: false)
        try (manifestLines.joined(separator: "\n") + "\n").write(to: manifestURL, atomically: true, encoding: .utf8)

        if self.fileManager.fileExists(atPath: destinationURL.path) {
            try self.fileManager.removeItem(at: destinationURL)
        }
        try self.zip(stagingDirectory: staging, destinationURL: destinationURL)
    }

    // MARK: - Kept dictation (a recording whose transcription timed out)

    /// Kept apart from history audio, so history pruning never treats it as an orphan. One file at
    /// most; it lives until it is transcribed or a newer dictation succeeds.
    private let keptFolder = "KeptDictation"
    private let keptQueue = DispatchQueue(label: "DictationAudioHistoryStore.kept", qos: .utility)

    /// Writes the kept recording off the calling thread, replacing any earlier one. Saves and
    /// deletes run in call order.
    func saveKeptDictation(_ snapshot: DictationAudioSnapshot, stoppedAt: Date) {
        self.keptQueue.async {
            do {
                let directory = try self.keptDirectory(createIfNeeded: true)
                self.removeKeptFiles(in: directory)
                let url = directory.appendingPathComponent(Self.keptFileName(stoppedAt: stoppedAt), isDirectory: false)
                try Self.wavData(from: snapshot).write(to: url, options: .atomic)
                DebugLogger.shared.info("Kept dictation saved audioMs=\(snapshot.durationMilliseconds)", source: "DictationAudioHistoryStore")
            } catch {
                DebugLogger.shared.error("Kept dictation could not be saved: \(error.localizedDescription)", source: "DictationAudioHistoryStore")
            }
        }
    }

    func deleteKeptDictation() {
        self.keptQueue.async {
            guard let directory = try? self.keptDirectory(createIfNeeded: false) else { return }
            self.removeKeptFiles(in: directory)
        }
    }

    /// The user cleared history or deleted all saved audio: the kept recording goes too, and
    /// ASRService is told to forget its copy.
    func discardKeptDictation() {
        self.deleteKeptDictation()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.keptDictationDiscardedNotification, object: nil)
        }
    }

    /// When the kept recording on disk stopped, if there is one. Waits for pending saves.
    func keptDictationStoppedAt() -> Date? {
        self.keptQueue.sync { self.keptFileURL().flatMap { Self.keptStoppedAt(fileName: $0.lastPathComponent) } }
    }

    /// The kept recording's samples (16 kHz mono), if there is one. Waits for pending saves.
    func loadKeptDictation() -> DictationAudioSnapshot? {
        self.keptQueue.sync {
            guard let url = self.keptFileURL(), let data = try? Data(contentsOf: url) else { return nil }
            return Self.snapshot(fromWAV: data)
        }
    }

    private func keptDirectory(createIfNeeded: Bool) throws -> URL {
        let directory = try self.rootDirectory().appendingPathComponent(self.keptFolder, isDirectory: true)
        if createIfNeeded {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func keptFileURL() -> URL? {
        guard let directory = try? self.keptDirectory(createIfNeeded: false) else { return nil }
        let files = (try? self.fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "wav" }.max { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeKeptFiles(in directory: URL) {
        let files = (try? self.fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "wav" {
            try? self.fileManager.removeItem(at: file)
        }
    }

    static func keptFileName(stoppedAt: Date) -> String {
        "kept-\(Int64((stoppedAt.timeIntervalSince1970 * 1000).rounded())).wav"
    }

    static func keptStoppedAt(fileName: String) -> Date? {
        guard fileName.hasPrefix("kept-"), fileName.hasSuffix(".wav"),
              let milliseconds = Int64(fileName.dropFirst(5).dropLast(4))
        else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// Reads back what `wavData(from:)` writes: 16-bit PCM, little-endian, one data chunk.
    static func snapshot(fromWAV data: Data) -> DictationAudioSnapshot? {
        guard data.count >= 44,
              String(data: data.prefix(4), encoding: .ascii) == "RIFF",
              String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE"
        else { return nil }
        func uint16(at offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func uint32(at offset: Int) -> Int { uint16(at: offset) | uint16(at: offset + 2) << 16 }
        let channels = uint16(at: 22)
        let sampleRate = uint32(at: 24)
        let bitsPerSample = uint16(at: 34)
        guard bitsPerSample == 16, channels > 0, sampleRate > 0,
              String(data: data.subdata(in: 36..<40), encoding: .ascii) == "data"
        else { return nil }
        let byteCount = min(uint32(at: 40), data.count - 44)
        var samples = [Float]()
        samples.reserveCapacity(byteCount / 2)
        var offset = 44
        while offset + 1 < 44 + byteCount {
            let value = Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
            samples.append(Float(value) / Float(Int16.max))
            offset += 2
        }
        return DictationAudioSnapshot(samples: samples, sampleRate: sampleRate, channels: channels)
    }

    private func audioDirectory(createIfNeeded: Bool = true) throws -> URL {
        let directory = try self.rootDirectory().appendingPathComponent(self.audioFolder, isDirectory: true)
        if createIfNeeded {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func audioFileURL(fileName: String, createIfNeeded: Bool) -> URL? {
        guard let safeFileName = self.safeAudioFileName(fileName),
              let directory = try? self.audioDirectory(createIfNeeded: createIfNeeded)
        else {
            return nil
        }
        return directory.appendingPathComponent(safeFileName, isDirectory: false)
    }

    private func safeAudioFileName(_ fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastPathComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        guard trimmed == lastPathComponent,
              lastPathComponent != ".",
              lastPathComponent != "..",
              URL(fileURLWithPath: lastPathComponent).pathExtension.lowercased() == "wav"
        else {
            return nil
        }

        return lastPathComponent
    }

    private func audioFileName(entryID: UUID, timestamp: Date) -> String {
        "\(Self.fileTimestampFormatter.string(from: timestamp))_\(entryID.uuidString.prefix(8)).wav"
    }

    private func zip(stagingDirectory: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destinationURL.path, "manifest.jsonl", "audio"]
        process.currentDirectoryURL = stagingDirectory

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw DictationAudioHistoryError.zipFailed(message)
        }
    }

    private static func wavData(from snapshot: DictationAudioSnapshot) -> Data {
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let dataByteCount = snapshot.samples.count * bytesPerSample
        let byteRate = snapshot.sampleRate * snapshot.channels * bytesPerSample
        let blockAlign = snapshot.channels * bytesPerSample

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        data.append(contentsOf: Array("RIFF".utf8))
        Self.appendUInt32LE(UInt32(36 + dataByteCount), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        Self.appendUInt32LE(16, to: &data)
        Self.appendUInt16LE(1, to: &data)
        Self.appendUInt16LE(UInt16(snapshot.channels), to: &data)
        Self.appendUInt32LE(UInt32(snapshot.sampleRate), to: &data)
        Self.appendUInt32LE(UInt32(byteRate), to: &data)
        Self.appendUInt16LE(UInt16(blockAlign), to: &data)
        Self.appendUInt16LE(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: Array("data".utf8))
        Self.appendUInt32LE(UInt32(dataByteCount), to: &data)

        for sample in snapshot.samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16((clamped * Float(Int16.max)).rounded())
            Self.appendInt16LE(scaled, to: &data)
        }
        return data
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendInt16LE(_ value: Int16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct AudioManifestRow: Encodable {
    let audio: String
    let text: String
    let rawTranscript: String
    let finalTranscript: String
    let timestamp: String
    let durationMilliseconds: Int
    let sampleRate: Int
    let channels: Int
    let app: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case audio
        case text
        case rawTranscript = "raw_transcript"
        case finalTranscript = "final_transcript"
        case timestamp
        case durationMilliseconds = "duration_ms"
        case sampleRate = "sample_rate"
        case channels
        case app
        case model
    }
}
