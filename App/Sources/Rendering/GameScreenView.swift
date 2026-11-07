import SwiftUI
import MetalKit

struct ScreenUniforms {
    var filter: Int32
    var intensity: Float
    var sourceSize: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var time: Float
}

/// Draws the latest emulator frame with the theme's screen filter.
struct GameScreenView: UIViewRepresentable {
    let frame: FrameBuffer
    var style: ScreenStyle

    func makeCoordinator() -> Renderer { Renderer(frame: frame) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.style = style
    }

    final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        private let queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private let frame: FrameBuffer
        private var lastVersion: UInt64 = .max
        private let start = CACurrentMediaTime()
        var style = ScreenStyle()

        init(frame: FrameBuffer) {
            self.frame = frame
            device = MTLCreateSystemDefaultDevice()
            queue = device?.makeCommandQueue()
            super.init()
            buildPipeline()
        }

        private func buildPipeline() {
            guard let device, let library = device.makeDefaultLibrary() else { return }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "screen_vertex")
            desc.fragmentFunction = library.makeFunction(name: "screen_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        private func uploadFrame() {
            guard let device else { return }
            frame.read { pixels, w, h, version in
                guard w > 0, h > 0 else { return }
                if texture == nil || texture!.width != w || texture!.height != h {
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
                    desc.usage = .shaderRead
                    texture = device.makeTexture(descriptor: desc)
                    lastVersion = .max
                }
                guard version != lastVersion else { return }
                lastVersion = version
                texture?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
            }
        }

        func draw(in view: MTKView) {
            uploadFrame()
            guard let pipeline, let texture, let queue,
                  let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms = ScreenUniforms(
                filter: style.filter.shaderIndex,
                intensity: Float(style.intensity),
                sourceSize: SIMD2(Float(texture.width), Float(texture.height)),
                outputSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: Float(CACurrentMediaTime() - start))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScreenUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

/// The game screen with the theme's border, rounded corners and glow, sized to the right aspect ratio.
struct StyledGameScreen: View {
    let frame: FrameBuffer
    let system: GameSystem
    let style: ScreenStyle

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(in: geo.size)
            GameScreenView(frame: frame, style: style)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(style.borderColor.color, lineWidth: style.borderWidth)
                )
                .shadow(color: style.borderColor.color.opacity(style.glow), radius: 18 * style.glow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let native = system.screenSize
        let inner = CGSize(width: max(available.width - style.borderWidth * 2, 1),
                           height: max(available.height - style.borderWidth * 2, 1))
        var scale = min(inner.width / native.width, inner.height / native.height)
        if style.integerScaling {
            let pixelScale = UIScreen.main.scale
            scale = max(1, (scale * pixelScale).rounded(.down)) / pixelScale
        }
        return CGSize(width: native.width * scale + style.borderWidth * 2, height: native.height * scale + style.borderWidth * 2)
    }
}
