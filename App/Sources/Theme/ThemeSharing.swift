import SwiftUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import Compression

extension UTType {
    static let e4theme = UTType(exportedAs: "com.fuxkingjosh.emu4ios.theme")
}

enum ThemeSharingError: LocalizedError {
    case invalidData, newerVersion, tooLargeForLink
    var errorDescription: String? {
        switch self {
        case .invalidData: return "That doesn't look like an Emu4ios theme."
        case .newerVersion: return "This theme was made with a newer version of Emu4ios. Update the app to use it."
        case .tooLargeForLink: return "This theme has a photo background, so it's too big for a link or QR code. Share it as a file instead."
        }
    }
}

/// Turns themes into files, links and QR codes, and back.
enum ThemeSharing {
    static let linkPrefix = "emu4ios://theme?d="
    /// QR codes stop scanning reliably beyond roughly this many characters.
    static let maxQRLength = 2_800

    static func encode(_ theme: Theme, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(theme)
    }

    static func decode(_ data: Data) throws -> Theme {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        guard let theme = try? decoder.decode(Theme.self, from: data) else { throw ThemeSharingError.invalidData }
        if theme.schema > Theme.schemaVersion { throw ThemeSharingError.newerVersion }
        return theme
    }

    // MARK: Links

    static func link(for theme: Theme) throws -> URL {
        var shareable = theme
        shareable.isBuiltIn = false
        if shareable.background.imageData != nil { throw ThemeSharingError.tooLargeForLink }
        let json = try encode(shareable)
        let packed = try compress(json)
        let string = linkPrefix + packed.base64URLEncoded()
        guard let url = URL(string: string) else { throw ThemeSharingError.invalidData }
        return url
    }

    static func theme(fromLink url: URL) throws -> Theme {
        guard url.scheme == "emu4ios", url.host == "theme",
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" }),
              let value = item.value, let packed = Data(base64URLEncoded: value) else {
            throw ThemeSharingError.invalidData
        }
        return try decode(try decompress(packed))
    }

    // MARK: Files

    static func exportFile(for theme: Theme) throws -> URL {
        let safeName = theme.name.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "Theme" : safeName)
            .appendingPathExtension("e4theme")
        try encode(theme, pretty: true).write(to: url, options: .atomic)
        return url
    }

    // MARK: QR

    static func qrImage(for url: URL) -> UIImage? {
        let string = url.absoluteString
        guard string.count <= maxQRLength else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Compression (zlib, with a 4-byte length header)

    static func compress(_ data: Data) throws -> Data {
        let capacity = max(64, data.count + 64)
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ThemeSharingError.invalidData }
        var header = UInt32(data.count).bigEndian
        return Data(bytes: &header, count: 4) + out.prefix(written)
    }

    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 4 else { throw ThemeSharingError.invalidData }
        let size = Int(data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        guard size > 0, size < 20_000_000 else { throw ThemeSharingError.invalidData }
        let body = data.dropFirst(4)
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            body.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, body.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ThemeSharingError.invalidData }
        return out
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}

/// Lets SwiftUI's ShareLink / fileExporter hand out themes as .e4theme files.
struct ThemeFile: Transferable {
    let theme: Theme
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .e4theme) { file in
            SentTransferredFile(try ThemeSharing.exportFile(for: file.theme))
        }
    }
}
