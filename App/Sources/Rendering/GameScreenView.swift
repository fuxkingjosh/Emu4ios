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

/// The game screen with the theme's bezel, border, rounded corners and glow, sized to the right aspect ratio.
struct StyledGameScreen: View {
    let frame: FrameBuffer
    let system: GameSystem
    let style: ScreenStyle
    var accent: Color = .purple

    var body: some View {
        GeometryReader { geo in
            let t = style.bezel.thickness
            // Leave room for the frame: shrink the space the screen can use by the frame's thickness.
            let inner = CGSize(width: geo.size.width / (1 + 2 * t.side),
                               height: geo.size.height / (1 + (t.top + t.bottom) * Double(system.screenSize.width / system.screenSize.height)))
            let size = fittedSize(in: inner)
            let side = size.width * t.side, top = size.width * t.top, bottom = size.width * t.bottom
            ZStack {
                if style.bezel != .none {
                    BezelView(bezel: style.bezel, color: style.bezelColor.color, accent: accent,
                              screenSize: size, insets: EdgeInsets(top: top, leading: side, bottom: bottom, trailing: side))
                }
                GameScreenView(frame: frame, style: style)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .strokeBorder(style.borderColor.color, lineWidth: style.borderWidth)
                    )
                    .shadow(color: style.borderColor.color.opacity(style.glow), radius: 18 * style.glow)
                    .offset(y: (top - bottom) / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let native = system.screenSize
        let inner = CGSize(width: max(available.width - style.borderWidth * 2, 1),
                           height: max(available.height - style.borderWidth * 2, 1))
        var scale = min(inner.width / native.width, inner.height / native.height)
        if style.integerScaling && system != .ps1 {
            let pixelScale = UIScreen.main.scale
            scale = max(1, (scale * pixelScale).rounded(.down)) / pixelScale
        }
        return CGSize(width: native.width * scale + style.borderWidth * 2, height: native.height * scale + style.borderWidth * 2)
    }
}

/// Decorative frames drawn around the game screen. Original designs (no console branding).
struct BezelView: View {
    let bezel: BezelStyle
    let color: Color
    let accent: Color
    let screenSize: CGSize
    let insets: EdgeInsets

    var body: some View {
        let w = screenSize.width + insets.leading + insets.trailing
        let h = screenSize.height + insets.top + insets.bottom
        let unit = screenSize.width / 100
        ZStack {
            switch bezel {
            case .none:
                EmptyView()
            case .handheld:
                RoundedRectangle(cornerRadius: unit * 7, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.95), color], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: unit * 7, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.4), radius: unit * 2, y: unit)
                HStack(spacing: unit) {
                    Circle().fill(Color.red).frame(width: unit * 1.6, height: unit * 1.6).shadow(color: .red, radius: unit)
                    Text("POWER").font(.system(size: max(unit * 2, 6), weight: .bold)).foregroundStyle(.white.opacity(0.45))
                }
                .position(x: insets.leading / 2 + unit * 2.5, y: h / 2)
                .rotationEffect(.degrees(-90))
            case .brick:
                UnevenRoundedRectangle(topLeadingRadius: unit * 3, bottomLeadingRadius: unit * 3,
                                       bottomTrailingRadius: unit * 12, topTrailingRadius: unit * 3, style: .continuous)
                    .fill(color)
                    .overlay(alignment: .bottomLeading) {
                        Text("Emu4ios POCKET")
                            .font(.system(size: max(unit * 3.6, 8), weight: .heavy, design: .rounded).italic())
                            .foregroundStyle(accent.opacity(0.85))
                            .padding(.leading, insets.leading)
                            .padding(.bottom, insets.bottom * 0.3)
                    }
                HStack(spacing: unit * 1.5) {
                    Circle().fill(Color.red.opacity(0.9)).frame(width: unit * 1.8)
                    Text("BATTERY").font(.system(size: max(unit * 1.8, 6), weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(height: unit * 2)
                .position(x: insets.leading + unit * 9, y: insets.top / 2)
            case .crtTV:
                RoundedRectangle(cornerRadius: unit * 6, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: unit * 6, style: .continuous).strokeBorder(.black.opacity(0.35), lineWidth: unit * 0.8))
                RoundedRectangle(cornerRadius: unit * 4, style: .continuous)
                    .fill(Color.black)
                    .frame(width: screenSize.width + unit * 3, height: screenSize.height + unit * 3)
                    .offset(y: (insets.top - insets.bottom) / 2)
                HStack(spacing: unit * 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color.black.opacity(0.45)).frame(width: unit * 2.6).overlay(Circle().stroke(.white.opacity(0.2)))
                    }
                }
                .position(x: w - insets.trailing - unit * 8, y: h - insets.bottom / 2)
            case .arcade:
                RoundedRectangle(cornerRadius: unit * 2, style: .continuous)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: unit * 2, style: .continuous)
                        .strokeBorder(accent, lineWidth: unit * 0.7))
                    .shadow(color: accent.opacity(0.9), radius: unit * 3)
                    .shadow(color: accent.opacity(0.5), radius: unit * 8)
            case .glass:
                RoundedRectangle(cornerRadius: unit * 5, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: unit * 5, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
        }
        .frame(width: w, height: h)
    }
}
