import Foundation
import UIKit

/// Finds official game names and box art automatically.
///
/// 1. Fingerprints the game file (CRC32) and looks it up in the open No-Intro database from libretro,
///    which gives the exact game name, e.g. "Pokemon - FireRed Version (USA, Europe)".
/// 2. Downloads that game's box art from the libretro-thumbnails collection.
actor CoverArtService {
    static let shared = CoverArtService()

    struct Match: Sendable {
        let databaseName: String
        let cleanTitle: String
        let image: UIImage?
    }

    private var databases: [GameSystem: [UInt32: String]] = [:]
    private var serials: [GameSystem: [String: String]] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoCoverArt") as? Bool ?? true
    }

    private static func repoName(_ system: GameSystem) -> (dat: String, thumbs: String) {
        (system.thumbnailDatabase, system.thumbnailRepo)
    }

    /// Systems that share box art collections (a GB game may be filed under GBC and the other way round).
    private static func relatives(of system: GameSystem) -> [GameSystem] {
        switch system {
        case .gb: return [.gbc]
        case .gbc: return [.gb]
        case .ngp: return [.ngpc]
        case .ngpc: return [.ngp]
        case .wswan: return [.wswanc]
        case .wswanc: return [.wswan]
        case .pce: return [.supergrafx]
        case .supergrafx: return [.pce]
        case .sms: return [.gamegear, .sg1000]
        default: return []
        }
    }

    /// Bytes to skip before fingerprinting (copier / emulator headers that No-Intro leaves out).
    private static func headerSize(_ data: Data, system: GameSystem) -> Int {
        switch system {
        case .nes: return data.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A]) ? 16 : 0
        case .snes: return data.count % 1024 == 512 ? 512 : 0
        case .lynx: return data.prefix(4) == Data("LYNX".utf8) ? 64 : 0
        case .atari7800: return data.count > 128 && data[1..<10] == Data("ATARI7800".utf8) ? 128 : 0
        default: return 0
        }
    }

    // MARK: Lookup

    func lookup(romURL: URL, system: GameSystem) async -> Match? {
        if !system.matchesByChecksum { return await lookupByName(romURL: romURL, system: system) }
        guard let data = try? Data(contentsOf: romURL, options: .mappedIfSafe) else { return nil }
        let skip = Self.headerSize(data, system: system)
        let crc = data.withUnsafeBytes { raw -> UInt32 in
            let base = raw.bindMemory(to: Bytef.self).baseAddress.map { $0 + skip }
            return UInt32(crc32(0, base, uInt(max(0, data.count - skip))))
        }
        let names = await database(for: system)
        var name = names[crc]
        // GBA games also carry a 4-letter game code; use it if the exact dump isn't in the database.
        if name == nil, system == .gba, data.count > 0xB0 {
            let code = String(decoding: data[0xAC..<0xB0], as: UTF8.self)
            name = serials[system]?[code]
        }
        // Different system folder (e.g. GB game that's in the GBC set)?
        if name == nil {
            for other in Self.relatives(of: system) {
                if let n = await database(for: other)[crc] { name = n; break }
            }
        }
        // Hacks, translations and odd dumps: fall back to the file name.
        guard let name else { return await lookupByName(romURL: romURL, system: system) }
        let image = await boxArt(named: name, system: system)
        return Match(databaseName: name, cleanTitle: Self.clean(name), image: image)
    }

    /// Disc images are too big to fingerprint quickly (and computer games have no database), so their art
    /// is matched by file name — most dumps already use the official "Game Name (USA)" naming.
    private func lookupByName(romURL: URL, system: GameSystem) async -> Match? {
        var name = romURL.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(of: #"\s*\(Track \d+\)"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^\s*\d{3,5}\s*[-–.]\s*"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "_", with: " ")
        var candidates = [name]
        let noDisc = name.replacingOccurrences(of: #"\s*\(Disc \d+\)"#, with: "", options: .regularExpression)
        if noDisc != name { candidates.append(noDisc) }
        for region in ["USA", "Europe", "Japan"] where !name.contains("(") {
            candidates.append("\(name) (\(region))")
        }
        for candidate in candidates {
            if let image = await boxArt(named: candidate, system: system, searchOtherSystems: false) {
                return Match(databaseName: candidate, cleanTitle: Self.clean(candidate), image: image)
            }
        }
        return nil
    }

    /// "Pokemon - FireRed Version (USA, Europe) (Rev 1)" → "Pokemon - FireRed Version"
    static func clean(_ name: String) -> String {
        var s = name
        while let r = s.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Box art

    private func boxArt(named name: String, system: GameSystem, searchOtherSystems: Bool = true) async -> UIImage? {
        // libretro replaces these characters in file names.
        let safe = name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : String($0) }.joined()
        var candidates = [safe]
        // Fall back to the same game without revision tags, then without any tags.
        let noRev = safe.replacingOccurrences(of: #"\s*\((Rev|v)\s*[^)]*\)"#, with: "", options: .regularExpression)
        if noRev != safe { candidates.append(noRev) }
        let systems = searchOtherSystems ? [system] + Self.relatives(of: system) : [system]
        for system in systems {
            let repo = Self.repoName(system).thumbs
            for candidate in candidates {
                guard let encoded = candidate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(repo)/master/Named_Boxarts/\(encoded).png"),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: data) else { continue }
                return image
            }
        }
        return nil
    }

    // MARK: Database (downloaded once per system, then cached)

    private func database(for system: GameSystem) async -> [UInt32: String] {
        if let cached = databases[system] { return cached }
        let file = Self.cacheFolder.appendingPathComponent("\(system.rawValue).dat")
        var text = try? String(contentsOf: file, encoding: .utf8)
        if text == nil {
            let datName = Self.repoName(system).dat
            if let encoded = datName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/\(encoded).dat"),
               let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                try? data.write(to: file, options: .atomic)
                text = String(decoding: data, as: UTF8.self)
            }
        }
        var byCRC: [UInt32: String] = [:]
        var bySerial: [String: String] = [:]
        text?.enumerateLines { line, _ in
            // rom ( name "Game (USA).gba" size 123 crc DD88761C md5 ... serial "BPRE" )
            guard line.contains("rom ("),
                  let nameRange = line.range(of: #"name "([^"]+)""#, options: .regularExpression),
                  let crcRange = line.range(of: #"crc ([0-9A-Fa-f]{8})"#, options: .regularExpression) else { return }
            let fileName = String(line[nameRange].dropFirst(6).dropLast())
            let gameName = (fileName as NSString).deletingPathExtension
            if let crc = UInt32(line[crcRange].dropFirst(4), radix: 16) { byCRC[crc] = gameName }
            if let serialRange = line.range(of: #"serial "([A-Z0-9]{4})""#, options: .regularExpression) {
                let serial = String(line[serialRange].dropFirst(8).dropLast())
                // Prefer USA releases for the serial fallback.
                if bySerial[serial] == nil || gameName.contains("USA") { bySerial[serial] = gameName }
            }
        }
        if !byCRC.isEmpty { databases[system] = byCRC; serials[system] = bySerial }
        return byCRC
    }

    private static var cacheFolder: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameDatabase", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
