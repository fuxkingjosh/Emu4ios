import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Turns image data (PNG, JPEG, HEIC or animated GIF/APNG) into a UIImage that animates in UIImageView.
enum AnimatedImage {
    private static let cache = NSCache<NSData, UIImage>()

    static func image(from data: Data) -> UIImage? {
        if let cached = cache.object(forKey: data as NSData) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        let result: UIImage?
        if count <= 1 {
            result = UIImage(data: data)
        } else {
            var frames: [UIImage] = []
            var duration = 0.0
            // Cap very long GIFs so they can't eat all the memory.
            for i in 0..<min(count, 300) {
                guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                frames.append(UIImage(cgImage: cg))
                duration += frameDuration(source, i)
            }
            result = UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
        }
        if let result { cache.setObject(result, forKey: data as NSData) }
        return result
    }

    static func isAnimated(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private static func frameDuration(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
            ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)
            ?? 0.1
        return value < 0.02 ? 0.1 : value
    }

    /// Shrinks still pictures so themes stay small; animated GIFs are kept as-is.
    static func prepareForTheme(_ data: Data, maxSide: CGFloat = 900) -> Data {
        if isAnimated(data) { return data }
        guard let image = UIImage(data: data) else { return data }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.pngData() ?? data
    }

    static let pickableTypes: [UTType] = [.gif, .png, .jpeg, .heic, .webP, .image]
}

/// SwiftUI view that plays animated GIFs.
struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode
        view.image = AnimatedImage.image(from: data)
        if view.image?.images != nil { view.startAnimating() }
    }
}
