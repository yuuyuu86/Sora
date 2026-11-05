import MetalKit
import simd
import ImageIO

private struct Uniforms {
    var rt: SIMD4<Float>
    var sun: SIMD4<Float>
    var moon: SIMD4<Float>
    var w1: SIMD4<Float>
    var w2: SIMD4<Float>
    var misc: SIMD4<Float>
}

/// Metal で描く草原の背景。省電力のため 1x 解像度・30fps で描画する。
final class MetalLandscapeView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let skyPipeline: MTLRenderPipelineState
    private let grassPipeline: MTLRenderPipelineState
    private var cloudOffset = SIMD2<Float>(0, 0)
    private var lastTime = CACurrentMediaTime()
    private var grassCount: UInt32 = 32000

    init?(sceneFrame frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        do {
            let lib = try device.makeLibrary(source: meadowShaderSource, options: nil)
            func pipe(_ v: String, _ f: String) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                d.rasterSampleCount = 4
                return try device.makeRenderPipelineState(descriptor: d)
            }
            skyPipeline = try pipe("skyVertex", "skyFragment")
            grassPipeline = try pipe("grassVertex", "grassFragment")
        } catch {
            NSLog("Sora: Metal shader error: \(error)")
            return nil
        }
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        sampleCount = 4
        preferredFramesPerSecond = 30
        autoResizeDrawable = false
        framebufferOnly = true
        delegate = self
        updateDrawableSize()
    }

    required init(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        // 空は柔らかいので 1x で十分（Retina の 1/4 の負荷）
        drawableSize = CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - lastTime))
        lastTime = now
        guard let rpd = currentRenderPassDescriptor, let drawable = currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encode(enc, size: drawableSize, dt: dt)
        cb.present(drawable)
        cb.commit()
    }

    private func encode(_ enc: MTLRenderCommandEncoder, size: CGSize, dt: Float) {
        let a = Atmosphere.shared
        let s = AppSettings.shared
        let p = a.params

        // 雲は風に流される
        let speed = Float(0.012 + abs(p.wind) * 0.06)
        cloudOffset.x += (p.wind >= 0 ? -1 : 1) * speed * dt
        cloudOffset.y += speed * 0.25 * dt

        // 光や色の変化の強さ：弱いほど穏やかな昼に寄せる
        let st = s.lightStrength
        let alt = 0.55 + (a.sunAltitude - 0.55) * st
        let prog = 0.5 + (a.sunProgress - 0.5) * st
        let sunDir = simd_normalize(SIMD3<Float>(Float(-0.75 + 1.5 * prog), Float(alt * 0.55), 1))
        let moonUp = sin(.pi * a.moonProgress)
        let moonDir = simd_normalize(SIMD3<Float>(Float(-0.7 + 1.4 * a.moonProgress), Float(moonUp * 0.42), 1))
        let moonVis = Float(max(0, min(1, (-alt + 0.05) * 5)))

        let w = Float(size.width), h = Float(size.height)
        var u = Uniforms(
            rt: [w, h, Float(a.time), w / max(h, 1)],
            sun: SIMD4(sunDir, 2.6),
            moon: SIMD4(moonDir, moonVis),
            w1: [Float(p.cloud), Float(p.rain), Float(p.snow), Float(p.fog)],
            w2: [Float(a.flash * (0.4 + 0.6 * s.intensity)), Float(p.wind), Float(a.snowGround), 1.25 + 1.3 * moonVis],
            misc: [s.showSunMoon ? 1 : 0, cloudOffset.x, cloudOffset.y, Float(s.intensity)])

        enc.setRenderPipelineState(skyPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setRenderPipelineState(grassPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        var count = UInt32(Double(grassCount) * (0.5 + 0.5 * s.intensity))
        enc.setVertexBytes(&count, length: 4, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 7, instanceCount: Int(count))
        enc.endEncoding()
    }

    /// 確認用：1枚だけオフスクリーンで描いて PNG に保存する
    func snapshot(size: CGSize, to url: URL) {
        guard let device else { return }
        let w = Int(size.width), h = Int(size.height)
        let md = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        md.textureType = .type2DMultisample; md.sampleCount = 4; md.usage = .renderTarget; md.storageMode = .private
        let rd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        rd.usage = [.renderTarget, .shaderRead]; rd.storageMode = .shared
        guard let msaa = device.makeTexture(descriptor: md), let out = device.makeTexture(descriptor: rd),
              let cb = queue.makeCommandBuffer() else { return }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = msaa
        rpd.colorAttachments[0].resolveTexture = out
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encode(enc, size: size, dt: 0)
        cb.commit(); cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        out.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let img = ctx?.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
