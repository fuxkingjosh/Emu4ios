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
        switch system {
        case .gb: return ("Nintendo - Game Boy", "Nintendo_-_Game_Boy")
        case .gbc: return ("Nintendo - Game Boy Color", "Nintendo_-_Game_Boy_Color")
        case .gba: return ("Nintendo - Game Boy Advance", "Nintendo_-_Game_Boy_Advance")
        }
    }

    // MARK: Lookup

    func lookup(romURL: URL, system: GameSystem) async -> Match? {
        guard let data = try? Data(contentsOf: romURL, options: .mappedIfSafe) else { return nil }
        let crc = data.withUnsafeBytes { raw -> UInt32 in
            UInt32(crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
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
            for other in GameSystem.allCases where other != system {
                if let n = await database(for: other)[crc] { name = n; break }
            }
        }
        guard let name else { return nil }
        let image = await boxArt(named: name, system: system)
        return Match(databaseName: name, cleanTitle: Self.clean(name), image: image)
    }

    /// "Pokemon - FireRed Version (USA, Europe) (Rev 1)" → "Pokemon - FireRed Version"
    static func clean(_ name: String) -> String {
        var s = name
        while let r = s.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Box art

    private func boxArt(named name: String, system: GameSystem) async -> UIImage? {
        // libretro replaces these characters in file names.
        let safe = name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : String($0) }.joined()
        var candidates = [safe]
        // Fall back to the same game without revision tags, then without any tags.
        let noRev = safe.replacingOccurrences(of: #"\s*\((Rev|v)\s*[^)]*\)"#, with: "", options: .regularExpression)
        if noRev != safe { candidates.append(noRev) }
        for system in [system] + GameSystem.allCases.filter({ $0 != system }) {
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
