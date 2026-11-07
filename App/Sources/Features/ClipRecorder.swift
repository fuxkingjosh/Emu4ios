import ReplayKit
import Photos

/// Keeps the last ~30 seconds of gameplay buffered (ReplayKit clip buffering) so a clip can be saved any time.
final class ClipRecorder: @unchecked Sendable {
    static let shared = ClipRecorder()
    private let recorder = RPScreenRecorder.shared()
    private var buffering = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "clipsEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "clipsEnabled") }
    }

    var clipLength: Double {
        get { UserDefaults.standard.object(forKey: "clipLength") as? Double ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: "clipLength") }
    }

    func startBuffering() {
        guard isEnabled, recorder.isAvailable, !buffering else { return }
        recorder.isMicrophoneEnabled = false
        recorder.startClipBuffering { [weak self] error in
            self?.buffering = (error == nil)
        }
    }

    func stopBuffering() {
        guard buffering else { return }
        buffering = false
        recorder.stopClipBuffering { _ in }
    }

    func exportLastClip(_ done: @escaping @Sendable (String) -> Void) {
        guard isEnabled else {
            done("Turn on Clips in Settings first")
            return
        }
        guard buffering else {
            done("Clip recording isn't running")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        recorder.exportClip(to: url, duration: clipLength) { error in
            if error != nil {
                done("Couldn't save the clip")
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    done("Allow Photos access to save clips")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }, completionHandler: { ok, _ in
                    try? FileManager.default.removeItem(at: url)
                    done(ok ? "Clip saved to Photos" : "Couldn't save the clip")
                })
            }
        }
    }
}
