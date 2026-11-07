import Foundation

/// Keeps battery saves, save states and themes in iCloud Drive so they follow you to other devices.
/// Works only once iCloud is enabled for the app in the Apple Developer account (see README);
/// until then `isAvailable` is false and everything stays local.
final class CloudSync: @unchecked Sendable {
    static let shared = CloudSync()

    enum Kind: String, CaseIterable {
        case save = "Saves", state = "Save States", theme = "Themes"
        var localFolder: URL {
            switch self {
            case .save: return AppPaths.saves
            case .state: return AppPaths.states
            case .theme: return AppPaths.themes
            }
        }
    }

    private let queue = DispatchQueue(label: "emu4ios.cloudsync", qos: .utility)
    private var containerURL: URL?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cloudSyncEnabled") }
    }

    var isAvailable: Bool { containerURL != nil }

    private init() {}

    /// Looks up the iCloud container in the background (Apple says not to do this on the main thread).
    func start(completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            self.containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true)
            if self.isEnabled { self.pullAll() }
            completion?()
        }
    }

    func didChangeFile(_ url: URL, kind: Kind) {
        guard isEnabled else { return }
        queue.async { self.push(url, kind: kind) }
    }

    func syncNow() {
        queue.async {
            for kind in Kind.allCases { self.pushFolder(kind) }
            self.pullAll()
        }
    }

    // MARK: - Private

    private func cloudURL(for local: URL, kind: Kind) -> URL? {
        guard let root = containerURL else { return nil }
        let relative = local.path.replacingOccurrences(of: kind.localFolder.path, with: "")
        return root.appendingPathComponent(kind.rawValue, isDirectory: true).appendingPathComponent(relative)
    }

    private func push(_ local: URL, kind: Kind) {
        guard let remote = cloudURL(for: local, kind: kind) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: remote.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: remote, options: .forReplacing, error: &error) { url in
            try? fm.removeItem(at: url)
            try? fm.copyItem(at: local, to: url)
        }
    }

    private func pushFolder(_ kind: Kind) {
        for file in files(in: kind.localFolder) { push(file, kind: kind) }
    }

    /// Copies down anything in iCloud that is newer than the local copy.
    private func pullAll() {
        guard let root = containerURL else { return }
        let fm = FileManager.default
        for kind in Kind.allCases {
            let remoteFolder = root.appendingPathComponent(kind.rawValue, isDirectory: true)
            for remote in files(in: remoteFolder) {
                let relative = remote.path.replacingOccurrences(of: remoteFolder.path, with: "")
                let local = kind.localFolder.appendingPathComponent(relative)
                if remote.pathExtension == "icloud" {
                    try? fm.startDownloadingUbiquitousItem(at: remote)
                    continue
                }
                let remoteDate = (try? remote.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let localDate = (try? local.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                guard remoteDate > localDate else { continue }
                try? fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: local)
                try? fm.copyItem(at: remote, to: local)
            }
        }
    }

    private func files(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return e.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }
}
