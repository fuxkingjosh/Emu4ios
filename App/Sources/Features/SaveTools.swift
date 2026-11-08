import Foundation
import AppleArchive
import System

/// Battery saves / memory cards: export, import (with automatic backups), and full backups.
enum SaveTools {
    static var backupsFolder: URL {
        let url = AppPaths.saves.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func saveURL(for game: Game) -> URL { AppPaths.saveFile(for: game) }

    static func hasSave(_ game: Game) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: saveURL(for: game).path)[.size] as? Int) ?? 0
        return size > 0
    }

    static func saveSize(_ game: Game) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: saveURL(for: game).path)[.size] as? Int) ?? 0
    }

    static func stateCount(_ game: Game) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.statesFolder(for: game).path)) ?? []
        return files.filter { $0.hasSuffix(".state") }.count
    }

    /// A copy named after the game, ready for the share sheet.
    static func exportCopy(for game: Game) throws -> URL {
        let ext = game.system == .ps1 ? "srm" : "sav"
        let safe = game.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: saveURL(for: game), to: url)
        return url
    }

    /// Replaces a game's save, keeping the old one in Saves › Backups.
    static func importSave(from source: URL, into game: Game) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        guard !data.isEmpty, data.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        try backup(game)
        try data.write(to: saveURL(for: game), options: .atomic)
        CloudSync.shared.didChangeFile(saveURL(for: game), kind: .save)
    }

    static func deleteSave(_ game: Game) throws {
        try backup(game)
        try? FileManager.default.removeItem(at: saveURL(for: game))
    }

    @discardableResult
    static func backup(_ game: Game) throws -> URL? {
        guard hasSave(game) else { return nil }
        let stamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let base = saveURL(for: game).deletingPathExtension().lastPathComponent
        let url = backupsFolder.appendingPathComponent("\(base) \(stamp).bak")
        try FileManager.default.copyItem(at: saveURL(for: game), to: url)
        return url
    }

    static func backups(for game: Game) -> [URL] {
        let base = saveURL(for: game).deletingPathExtension().lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(base + " ") && $0.pathExtension == "bak" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func restore(_ backupURL: URL, into game: Game) throws {
        let data = try Data(contentsOf: backupURL)
        try backup(game)
        try data.write(to: saveURL(for: game), options: .atomic)
    }

    // MARK: Full backup (.e4backup = Apple Archive of Saves, Save States and Themes)

    static func makeFullBackup() throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Emu4ios Backup", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for folder in [AppPaths.saves, AppPaths.states, AppPaths.themes] {
            try FileManager.default.copyItem(at: folder, to: staging.appendingPathComponent(folder.lastPathComponent))
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("Emu4ios Backup \(Date.now.formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).e4backup")
        try? FileManager.default.removeItem(at: out)
        try archive(directory: staging, to: out)
        try? FileManager.default.removeItem(at: staging)
        return out
    }

    /// Restores saves, states and themes from a backup. Existing files with the same name are replaced.
    static func restoreFullBackup(from source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try extract(archive: source, to: staging)
        for folder in [AppPaths.saves, AppPaths.states, AppPaths.themes] {
            let restored = staging.appendingPathComponent(folder.lastPathComponent)
            guard let e = FileManager.default.enumerator(at: restored, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let file as URL in e where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                let relative = file.path.replacingOccurrences(of: restored.path + "/", with: "")
                let target = folder.appendingPathComponent(relative)
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: file, to: target)
            }
        }
    }

    private static func archive(directory: URL, to output: URL) throws {
        guard let file = ArchiveByteStream.fileStream(path: FilePath(output.path), mode: .writeOnly,
                                                       options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644)),
              let compressor = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file),
              let encoder = ArchiveStream.encodeStream(writingTo: compressor) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? encoder.close(); try? compressor.close(); try? file.close() }
        guard let keys = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM") else { throw CocoaError(.fileWriteUnknown) }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
    }

    private static func extract(archive: URL, to directory: URL) throws {
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .readOnly, options: [],
                                                       permissions: FilePermissions(rawValue: 0o644)),
              let decompressor = ArchiveByteStream.decompressionStream(readingFrom: file),
              let decoder = ArchiveStream.decodeStream(readingFrom: decompressor),
              let extractor = ArchiveStream.extractStream(extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { try? extractor.close(); try? decoder.close(); try? decompressor.close(); try? file.close() }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    }
}
