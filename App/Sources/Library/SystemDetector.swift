import Foundation

/// Works out which console a game file belongs to. Unique extensions decide on their own;
/// shared ones (.bin, .iso, .cue, .chd, .pbp, .exe…) are identified by looking inside the file.
enum SystemDetector {
    static func detect(_ url: URL) -> GameSystem? {
        let ext = url.pathExtension.lowercased()
        if let system = GameSystem(fileExtension: ext), !GameSystem.sharedExtensions.contains(ext) { return system }
        switch ext {
        case "cue": return detectCue(url)
        case "iso", "img": return detectDisc(url, defaultSystem: ext == "iso" ? .psp : .ps1)
        case "bin": return detectBin(url)
        case "chd": return detectCHD(url)
        case "pbp": return detectPBP(url)
        case "exe": return isPlayStationEXE(url) ? .ps1 : .dos
        case "m3u": return detectPlaylist(url)
        case "ccd", "toc": return .ps1
        case "zip": return zipContainsDOSProgram(url) ? .dos : nil
        default: return GameSystem(fileExtension: ext)
        }
    }

    /// Consoles a file with this extension could belong to (for the "which console?" question).
    static func candidates(for fileName: String) -> [GameSystem] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "zip": return [.dos, .nes, .snes, .genesis, .gba, .n64, .atari2600]
        case "bin": return [.genesis, .ps1, .segacd, .atari2600, .atari5200, .atari7800]
        case "iso", "chd", "cue", "img": return [.ps1, .psp, .segacd, .pcecd]
        default:
            let list = GameSystem.allCases.filter { $0.fileExtensions.contains(ext) }
            return list.isEmpty ? GameSystem.available : list
        }
    }

    // MARK: Discs

    private static func read(_ url: URL, offset: UInt64 = 0, length: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        return (try? handle.read(upToCount: length)) ?? Data()
    }

    private static func contains(_ data: Data, _ text: String) -> Bool {
        data.range(of: Data(text.utf8)) != nil
    }

    /// Looks at the start of a data track for each console's signature.
    private static func signature(_ url: URL) -> GameSystem? {
        let head = read(url, length: 0x12000)
        if contains(head.prefix(0x220), "SEGADISCSYSTEM") || contains(head.prefix(0x220), "SEGA SEGASYSTEM") { return .segacd }
        if contains(head, "PSP GAME") || contains(head, "UMD_DATA") || contains(head, "PSP_GAME") { return .psp }
        if contains(head, "PLAYSTATION") { return .ps1 }
        if contains(head, "PC Engine CD-ROM SYSTEM") || contains(head, "PC-FX") { return .pcecd }
        return nil
    }

    private static func detectDisc(_ url: URL, defaultSystem: GameSystem) -> GameSystem {
        signature(url) ?? defaultSystem
    }

    private static func detectCue(_ url: URL) -> GameSystem? {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return .ps1 }
        var firstFile: String?
        var firstTrackIsAudio = false
        var sawTrack = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("FILE"), firstFile == nil,
               let a = line.firstIndex(of: "\""), let b = line.lastIndex(of: "\""), a < b {
                firstFile = String(line[line.index(after: a)..<b])
            }
            if upper.hasPrefix("TRACK"), !sawTrack {
                sawTrack = true
                firstTrackIsAudio = upper.contains("AUDIO")
            }
        }
        // PC Engine CDs start with an audio warning track; PlayStation and Sega CD discs start with data.
        if firstTrackIsAudio { return .pcecd }
        if let name = firstFile {
            let track = url.deletingLastPathComponent().appendingPathComponent(name)
            if let found = signature(track) { return found }
        }
        return .ps1
    }

    private static func detectBin(_ url: URL) -> GameSystem? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let head = read(url, length: 0x200)
        if head.count >= 0x104, String(data: head[0x100..<0x104], encoding: .ascii) == "SEGA" { return .genesis }
        if size > 0, size <= 64 * 1024 { return .atari2600 }
        if size > 8 * 1024 * 1024 { return signature(url) ?? .ps1 } // a CD image without its .cue
        // Cartridge-sized .bin without a Sega header: most likely a Genesis ROM (they don't all have one).
        return signature(url) ?? .genesis
    }

    private static func detectCHD(_ url: URL) -> GameSystem? {
        // CHD files are compressed, so the disc's signature isn't readable directly; use the folder or name as a hint.
        let hint = url.path.lowercased()
        if hint.contains("sega cd") || hint.contains("mega cd") || hint.contains("mega-cd") || hint.contains("segacd") { return .segacd }
        if hint.contains("pc engine") || hint.contains("turbografx") || hint.contains("pce") { return .pcecd }
        if hint.contains("psp") { return .psp }
        return .ps1
    }

    private static func detectPBP(_ url: URL) -> GameSystem {
        let header = read(url, length: 0x28)
        guard header.count >= 0x28, header.prefix(4) == Data([0, 0x50, 0x42, 0x50]) else { return .ps1 }
        let psarOffset = header[0x24..<0x28].withUnsafeBytes { UInt64($0.loadUnaligned(as: UInt32.self).littleEndian) }
        let psar = read(url, offset: psarOffset, length: 8)
        let tag = String(data: psar, encoding: .ascii) ?? ""
        return tag.hasPrefix("PSISOIMG") || tag.hasPrefix("PSTITLEI") ? .ps1 : .psp
    }

    private static func isPlayStationEXE(_ url: URL) -> Bool {
        read(url, length: 8) == Data("PS-X EXE".utf8)
    }

    private static func detectPlaylist(_ url: URL) -> GameSystem? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .ps1 }
        for line in text.components(separatedBy: .newlines) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
            let target = url.deletingLastPathComponent().appendingPathComponent(entry)
            return detect(target) ?? .ps1
        }
        return .ps1
    }

    // MARK: Zip archives

    private static func zipContainsDOSProgram(_ url: URL) -> Bool {
        guard let names = try? ZipArchive(url: url).entries.map(\.name) else { return false }
        return names.contains { ["exe", "com", "bat"].contains(($0 as NSString).pathExtension.lowercased()) }
    }
}

/// Minimal .zip reader (stored and deflated entries), enough to pull a game out of an archive.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    let data: Data
    let entries: [Entry]

    enum ZipError: Error { case notZip, unsupported, corrupt }

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        entries = try Self.readDirectory(data)
    }

    private static func u16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    private static func u32(_ d: Data, _ o: Int) -> Int { u16(d, o) | u16(d, o + 2) << 16 }

    private static func readDirectory(_ d: Data) throws -> [Entry] {
        guard d.count >= 22 else { throw ZipError.notZip }
        // End of central directory record: search backwards (it may be followed by a comment).
        var eocd = -1
        var i = d.count - 22
        let stop = max(0, d.count - 22 - 65_535)
        while i >= stop {
            if u32(d, i) == 0x06054B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = u16(d, eocd + 10)
        var p = u32(d, eocd + 16)
        var list: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(d, p) == 0x02014B50 else { throw ZipError.corrupt }
            let method = UInt16(u16(d, p + 10))
            let csize = u32(d, p + 20), usize = u32(d, p + 24)
            let nameLen = u16(d, p + 28), extraLen = u16(d, p + 30), commentLen = u16(d, p + 32)
            let offset = u32(d, p + 42)
            guard p + 46 + nameLen <= d.count else { throw ZipError.corrupt }
            let nameData = d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            list.append(Entry(name: name, method: method, compressedSize: csize, size: usize, localHeaderOffset: offset))
            p += 46 + nameLen + extraLen + commentLen
        }
        return list
    }

    func extract(_ entry: Entry) throws -> Data {
        let o = entry.localHeaderOffset
        guard o + 30 <= data.count, Self.u32(data, o) == 0x04034B50 else { throw ZipError.corrupt }
        let start = o + 30 + Self.u16(data, o + 26) + Self.u16(data, o + 28)
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0: return compressed
        case 8: return try Self.inflateRaw(compressed, expected: entry.size)
        default: throw ZipError.unsupported
        }
    }

    private static func inflateRaw(_ input: Data, expected: Int) throws -> Data {
        var output = Data(count: max(expected, 1))
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ZipError.corrupt }
        defer { inflateEnd(&stream) }
        let status: Int32 = input.withUnsafeBytes { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                stream.next_in = UnsafeMutablePointer(mutating: inBuf.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outBuf.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END || (status == Z_OK && stream.avail_out == 0) else { throw ZipError.corrupt }
        output.count = Int(stream.total_out)
        return output
    }
}
