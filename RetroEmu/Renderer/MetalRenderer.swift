// MetalRenderer.swift
// Metal 渲染管线，支持 Nearest / SharpBilinear / LCDGrid 三种滤镜

import Metal
import MetalKit
import UIKit

// 渲染滤镜模式
enum RenderFilter: Int, CaseIterable {
    case nearest       // 原始像素，无插值
    case sharpBilinear // 锐利双线性，推荐
    case lcdGrid       // LCD 格子，复古风
    case crt           // CRT 扫描线 + 桶形畸变
    case scanline      // 轻量扫描线
    case ntsc          // NTSC 色彩模拟
    case hd            // xBR 高清重制风格

    var displayName: String {
        switch self {
        case .nearest:       return "像素风"
        case .sharpBilinear: return "清晰增强"
        case .lcdGrid:       return "LCD 格子"
        case .crt:           return "CRT 显示器"
        case .scanline:      return "扫描线"
        case .ntsc:          return "NTSC 色彩"
        case .hd:            return "高清重制"
        }
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {

    // 内部存储（带下划线），通过计算属性暴露给 ExternalDisplayManager 扩展
    let _device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // 每种滤镜对应独立 pipeline
    private var pipelineNearest: MTLRenderPipelineState!
    private var pipelineSharpBilinear: MTLRenderPipelineState!
    private var pipelineLCDGrid: MTLRenderPipelineState!
    private var pipelineCRT: MTLRenderPipelineState!
    private var pipelineScanline: MTLRenderPipelineState!
    private var pipelineNTSC: MTLRenderPipelineState!
    private var pipelineHD: MTLRenderPipelineState!

    private var samplerNearest: MTLSamplerState!
    private var samplerLinear: MTLSamplerState!

    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer!

    private var frameWidth: Int = FrameSize.nesWidth
    private var frameHeight: Int = FrameSize.nesHeight
    private var aspectRatio: CGFloat = 256.0 / 240.0

    private let lock = NSLock()
    weak var _mtkView: MTKView?

    // 当前滤镜，外部可随时切换
    var filter: RenderFilter = .nearest

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self._device = device
        self.commandQueue = queue
        super.init()

        self._mtkView = mtkView
        mtkView.device = device
        mtkView.delegate = self
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60

        setupPipelines(mtkView: mtkView)
        setupSamplers()
        setupVertexBuffer()
    }

    // MARK: - 更新帧缓冲
    func updateFrame(_ buffer: UnsafePointer<UInt32>, width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }

        if texture == nil || frameWidth != width || frameHeight != height {
            frameWidth = width
            frameHeight = height
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            texture = _device.makeTexture(descriptor: desc)
        }

        texture?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: width * 4
        )
    }

    func setAspectRatio(width: CGFloat, height: CGFloat) {
        lock.lock()
        aspectRatio = width / height
        lock.unlock()
        updateVertexBuffer(viewSize: mtkView?.drawableSize ?? CGSize(width: 1, height: 1))
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateVertexBuffer(viewSize: size)
    }

    func draw(in view: MTKView) {
        lock.lock()
        let tex = texture
        let fw = frameWidth
        let fh = frameHeight
        let currentFilter = filter
        lock.unlock()

        guard let tex,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let pipeline: MTLRenderPipelineState
        let sampler: MTLSamplerState

        switch currentFilter {
        case .nearest:
            pipeline = pipelineNearest
            sampler = samplerNearest
        case .sharpBilinear:
            pipeline = pipelineSharpBilinear
            sampler = samplerNearest  // shader 内部自己做 linear
        case .lcdGrid:
            pipeline = pipelineLCDGrid
            sampler = samplerNearest
        case .crt:
            pipeline = pipelineCRT
            sampler = samplerLinear
        case .scanline:
            pipeline = pipelineScanline
            sampler = samplerNearest
        case .ntsc:
            pipeline = pipelineNTSC
            sampler = samplerLinear
        case .hd:
            pipeline = pipelineHD
            sampler = samplerNearest
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(tex, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)

        // 需要纹理尺寸的滤镜
        if currentFilter != .nearest {
            var texSize = SIMD2<Float>(Float(fw), Float(fh))
            encoder.setFragmentBytes(&texSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    // MARK: - Setup
    private func setupPipelines(mtkView: MTKView) {
        let library = _device.makeDefaultLibrary()!
        let fmt = mtkView.colorPixelFormat

        pipelineNearest       = makePipeline(library: library, frag: "fragmentShader",        fmt: fmt)
        pipelineSharpBilinear = makePipeline(library: library, frag: "fragmentSharpBilinear", fmt: fmt)
        pipelineLCDGrid       = makePipeline(library: library, frag: "fragmentLCDGrid",       fmt: fmt)
        pipelineCRT           = makePipeline(library: library, frag: "fragmentCRT",           fmt: fmt)
        pipelineScanline      = makePipeline(library: library, frag: "fragmentScanline",      fmt: fmt)
        pipelineNTSC          = makePipeline(library: library, frag: "fragmentNTSC",          fmt: fmt)
        pipelineHD            = makePipeline(library: library, frag: "fragmentXBR",           fmt: fmt)
    }

    private func makePipeline(library: MTLLibrary, frag: String, fmt: MTLPixelFormat) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = library.makeFunction(name: "vertexShader")!
        desc.fragmentFunction = library.makeFunction(name: frag)!
        desc.colorAttachments[0].pixelFormat = fmt
        return try! _device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupSamplers() {
        let nd = MTLSamplerDescriptor()
        nd.minFilter = .nearest
        nd.magFilter = .nearest
        nd.mipFilter = .notMipmapped
        samplerNearest = _device.makeSamplerState(descriptor: nd)

        let ld = MTLSamplerDescriptor()
        ld.minFilter = .linear
        ld.magFilter = .linear
        ld.mipFilter = .notMipmapped
        samplerLinear = _device.makeSamplerState(descriptor: ld)
    }

    private func setupVertexBuffer() {
        let vertices: [Float] = [
            -1,  1, 0, 0,
             1,  1, 1, 0,
            -1, -1, 0, 1,
             1, -1, 1, 1,
        ]
        vertexBuffer = _device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
    }

    private func updateVertexBuffer(viewSize: CGSize) {
        lock.lock()
        let ar = aspectRatio
        lock.unlock()

        let viewAR = viewSize.width / viewSize.height
        let (sx, sy): (Float, Float)
        if viewAR > ar {
            sy = 1.0
            sx = Float(ar / viewAR)
        } else {
            sx = 1.0
            sy = Float(viewAR / ar)
        }

        let vertices: [Float] = [
            -sx,  sy, 0, 0,
             sx,  sy, 1, 0,
            -sx, -sy, 0, 1,
             sx, -sy, 1, 1,
        ]
        vertexBuffer = _device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
    }
}
