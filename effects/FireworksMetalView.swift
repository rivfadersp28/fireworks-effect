import MetalKit
import SwiftUI
import simd

struct FireworksMetalView: UIViewRepresentable {
    let settings: FireworksSettings

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        context.coordinator.configure(for: view)
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Renderer.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(settings: settings)
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    private struct Firework {
        var position: SIMD2<Float>
        var startTime: Float
        var seed: Float
    }

    private struct FrameUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var fireworkCount: UInt32
        var explosionRadius: Float
        var particleSize: Float
        var glowIntensity: Float
        var glowRadius: Float
        var particleBlur: Float
        var fadeSpeed: Float
        var flightSpeed: Float
        var trailInstanceCount: Float
        var padding0: Float
        var padding1: Float
    }

    private let maxFireworks = 64
    private let spritesPerFirework = 2_000
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var particlePipelineState: MTLRenderPipelineState?
    private var toneMapPipelineState: MTLRenderPipelineState?
    private var accumulationTexture: MTLTexture?
    private var startTime = CACurrentMediaTime()
    private var fireworks: [Firework] = []
    private var settings = FireworksSettings()
    private weak var view: MTKView?

    func configure(for view: MTKView) {
        self.view = view

        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }

        view.device = device
        self.device = device
        commandQueue = device.makeCommandQueue()

        guard let library = device.makeDefaultLibrary(),
              let particleVertex = library.makeFunction(name: "fireworksParticleVertex"),
              let particleFragment = library.makeFunction(name: "fireworksParticleFragment"),
              let toneMapVertex = library.makeFunction(name: "toneMapVertex"),
              let toneMapFragment = library.makeFunction(name: "toneMapFragment")
        else {
            return
        }

        let particleDescriptor = MTLRenderPipelineDescriptor()
        particleDescriptor.vertexFunction = particleVertex
        particleDescriptor.fragmentFunction = particleFragment
        particleDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        particleDescriptor.colorAttachments[0].isBlendingEnabled = true
        particleDescriptor.colorAttachments[0].rgbBlendOperation = .add
        particleDescriptor.colorAttachments[0].alphaBlendOperation = .add
        particleDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        particleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        let toneMapDescriptor = MTLRenderPipelineDescriptor()
        toneMapDescriptor.vertexFunction = toneMapVertex
        toneMapDescriptor.fragmentFunction = toneMapFragment
        toneMapDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        particlePipelineState = try? device.makeRenderPipelineState(descriptor: particleDescriptor)
        toneMapPipelineState = try? device.makeRenderPipelineState(descriptor: toneMapDescriptor)
    }

    func update(settings: FireworksSettings) {
        self.settings = settings
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view else {
            return
        }

        let point = recognizer.location(in: view)
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }

        let normalized = SIMD2<Float>(
            Float(point.x / size.width),
            Float(point.y / size.height)
        )
        let now = Float(CACurrentMediaTime() - startTime)
        let seed = Float.random(in: 1...10_000)

        fireworks.append(Firework(position: normalized, startTime: now, seed: seed))
        if fireworks.count > maxFireworks {
            fireworks.removeFirst(fireworks.count - maxFireworks)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        accumulationTexture = nil
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue,
              let particlePipelineState,
              let toneMapPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let now = Float(CACurrentMediaTime() - startTime)
        fireworks.removeAll { now - $0.startTime > 3.4 }

        guard let accumulationTexture = makeAccumulationTexture(for: view) else {
            return
        }

        var uniforms = FrameUniforms(
            resolution: SIMD2<Float>(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            time: now,
            fireworkCount: UInt32(fireworks.count),
            explosionRadius: settings.explosionRadius,
            particleSize: settings.particleSize,
            glowIntensity: settings.glowIntensity,
            glowRadius: settings.glowRadius,
            particleBlur: settings.particleBlur,
            fadeSpeed: settings.fadeSpeed,
            flightSpeed: settings.flightSpeed,
            trailInstanceCount: settings.trailInstanceCount,
            padding0: 0,
            padding1: 0
        )

        let particlePassDescriptor = MTLRenderPassDescriptor()
        particlePassDescriptor.colorAttachments[0].texture = accumulationTexture
        particlePassDescriptor.colorAttachments[0].loadAction = .clear
        particlePassDescriptor.colorAttachments[0].storeAction = .store
        particlePassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: particlePassDescriptor) {
            encoder.setRenderPipelineState(particlePipelineState)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)

            fireworks.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress, !fireworks.isEmpty {
                    encoder.setVertexBytes(baseAddress, length: bytes.count, index: 1)
                    encoder.drawPrimitives(
                        type: .point,
                        vertexStart: 0,
                        vertexCount: fireworks.count * spritesPerFirework
                    )
                }
            }

            encoder.endEncoding()
        }

        if let renderPassDescriptor = view.currentRenderPassDescriptor,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.setRenderPipelineState(toneMapPipelineState)
            encoder.setFragmentTexture(accumulationTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeAccumulationTexture(for view: MTKView) -> MTLTexture? {
        guard let device else {
            return nil
        }

        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)
        if let accumulationTexture,
           accumulationTexture.width == width,
           accumulationTexture.height == height {
            return accumulationTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        accumulationTexture = device.makeTexture(descriptor: descriptor)
        return accumulationTexture
    }
}
