// PSPBridge.mm
// PPSSPP PlayStation Portable 核心桥接实现
// Vulkan/MoltenVK 硬件渲染 + IR Interpreter（App Store 合规）

#import "RetroEmuConfig.h"
#import "PSPBridge.h"
#import <vector>
#import <string>
#import <atomic>
#import <mutex>
#import <thread>
#import <unistd.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

// PSP 原生分辨率
static const int PSP_NATIVE_WIDTH  = 480;
static const int PSP_NATIVE_HEIGHT = 272;
static const int PSP_SAMPLE_RATE   = 44100;
static const int PSP_SPF           = PSP_SAMPLE_RATE / 60 + 16;

// ─────────────────────────────────────────────────────────────────────────────
// PPSSPP 头文件
// ─────────────────────────────────────────────────────────────────────────────
#include "Core/Config.h"
#include "Core/ConfigValues.h"
#include "Core/System.h"
#include "Core/CoreParameter.h"
#include "Core/Core.h"
#include "Core/CoreTiming.h"
#include "Core/HLE/sceCtrl.h"
#include "Common/System/System.h"
#include "Common/System/Display.h"
#include "Common/Thread/ThreadManager.h"
#include "Common/Thread/ThreadUtil.h"
#include "Common/TimeUtil.h"
#include "Common/File/VFS/VFS.h"
#include "Common/File/VFS/DirectoryReader.h"
#include "Common/File/FileUtil.h"
#include "Common/CPUDetect.h"
#include "Common/GraphicsContext.h"
#include "Common/GPU/Vulkan/VulkanContext.h"
#include "Common/GPU/Vulkan/VulkanLoader.h"
#include "Common/GPU/Vulkan/VulkanRenderManager.h"
#include "Common/GPU/thin3d.h"
#include "Common/GPU/thin3d_create.h"
#include "GPU/GPU.h"
#include "GPU/GPUCommon.h"
#include "GPU/Vulkan/VulkanUtil.h"

// PSP 按键位定义
#define PSP_CTRL_SELECT    0x000001
#define PSP_CTRL_START     0x000008
#define PSP_CTRL_UP        0x000010
#define PSP_CTRL_RIGHT     0x000020
#define PSP_CTRL_DOWN      0x000040
#define PSP_CTRL_LEFT      0x000080
#define PSP_CTRL_LTRIGGER  0x000100
#define PSP_CTRL_RTRIGGER  0x000200
#define PSP_CTRL_TRIANGLE  0x001000
#define PSP_CTRL_CIRCLE    0x002000
#define PSP_CTRL_CROSS     0x004000
#define PSP_CTRL_SQUARE    0x008000

// ─────────────────────────────────────────────────────────────────────────────
// 音频环形缓冲
// ─────────────────────────────────────────────────────────────────────────────
static const int AUDIO_RING_CAP = 44100;
static std::mutex           g_audioBufMutex;
static std::vector<int16_t> g_audioRing(AUDIO_RING_CAP, 0);
static int                  g_audioWrite = 0;
static int                  g_audioRead  = 0;
static int                  g_audioAvail = 0;

extern "C" void PSPBridge_PushAudio(const int32_t *samples, int numSamples, float volume) {
    if (!samples || numSamples <= 0) return;
    std::lock_guard<std::mutex> lock(g_audioBufMutex);
    int total = numSamples * 2;
    if (g_audioAvail + total > AUDIO_RING_CAP) {
        int drop = g_audioAvail + total - AUDIO_RING_CAP;
        g_audioRead  = (g_audioRead + drop) % AUDIO_RING_CAP;
        g_audioAvail -= drop;
    }
    for (int i = 0; i < total; i++) {
        int32_t s = (int32_t)(samples[i] * volume);
        if (s >  32767) s =  32767;
        if (s < -32768) s = -32768;
        g_audioRing[g_audioWrite] = (int16_t)s;
        g_audioWrite = (g_audioWrite + 1) % AUDIO_RING_CAP;
    }
    g_audioAvail += total;
}

extern "C" void PSPBridge_ClearAudio(void) {
    std::lock_guard<std::mutex> lock(g_audioBufMutex);
    g_audioWrite = 0;
    g_audioRead  = 0;
    g_audioAvail = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// IOSVulkanContext：封装 PPSSPP 的 Vulkan/MoltenVK 上下文
// ─────────────────────────────────────────────────────────────────────────────
enum class VulkanCtxState { PENDING, INITIALIZED, FAILED };

class RetroEmuVulkanContext : public GraphicsContext {
public:
    RetroEmuVulkanContext() {}
    ~RetroEmuVulkanContext() {
        delete g_Vulkan;
        g_Vulkan = nullptr;
    }

    // Phase 1：主线程调用，创建 Vulkan instance + device
    bool InitAPI() {
        init_glslang();
        std::string errorStr;
        bool loaded = false;

#if PPSSPP_PLATFORM(IOS_APP_STORE)
        // App Store 构建下 MoltenVK 静态链接进 App，vulkan_core.h 直接声明了
        // vkCreateInstance 等真实符号，VulkanLoader 也不再导出函数指针变量。
        // 因此这里既不能也不需要用 dlsym 覆写，交给链接器解析即可。
        loaded = (VulkanLoad(&errorStr) != false);
        if (!loaded) {
            NSLog(@"[PSPBridge] VulkanLoad 失败: %s", errorStr.c_str());
            state_ = VulkanCtxState::FAILED;
            return false;
        }
#else
        // MoltenVK 是静态链接的，用 dlopen(nullptr) 从当前进程加载 Vulkan 函数
        // 这样 VulkanLoader 的 dlsym 就能找到已静态链接的 MoltenVK 符号
        // 先尝试用进程自身句柄加载（静态链接 MoltenVK 的情况）
        void *processHandle = dlopen(nullptr, RTLD_LAZY | RTLD_GLOBAL);
        if (processHandle) {
            // 验证 vkCreateInstance 是否可用
            void *sym = dlsym(processHandle, "vkCreateInstance");
            if (sym) {
                // 手动设置 PPSSPP 的全局函数指针（绕过 VulkanLoadLibrary 的 dlopen 路径）
                // 通过 VulkanLoad 的 LOAD_GLOBAL_FUNC 宏需要 vulkanLibrary，
                // 但我们可以直接赋值
                using namespace PPSSPP_VK;
                vkCreateInstance = (PFN_vkCreateInstance)dlsym(processHandle, "vkCreateInstance");
                vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(processHandle, "vkGetInstanceProcAddr");
                vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)dlsym(processHandle, "vkGetDeviceProcAddr");
                vkEnumerateInstanceVersion = (PFN_vkEnumerateInstanceVersion)dlsym(processHandle, "vkEnumerateInstanceVersion");
                vkEnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)dlsym(processHandle, "vkEnumerateInstanceExtensionProperties");
                vkEnumerateInstanceLayerProperties = (PFN_vkEnumerateInstanceLayerProperties)dlsym(processHandle, "vkEnumerateInstanceLayerProperties");
                loaded = (vkCreateInstance && vkGetInstanceProcAddr && vkGetDeviceProcAddr
                          && vkEnumerateInstanceExtensionProperties && vkEnumerateInstanceLayerProperties);
                NSLog(@"[PSPBridge] 静态 MoltenVK 函数加载: %s", loaded ? "成功" : "失败");
            }
            dlclose(processHandle);
        }
        if (!loaded) {
            // 回退：尝试标准 VulkanLoad
            if (!VulkanLoad(&errorStr)) {
                NSLog(@"[PSPBridge] VulkanLoad 失败: %s", errorStr.c_str());
                state_ = VulkanCtxState::FAILED;
                return false;
            }
        }
#endif
        g_Vulkan = new VulkanContext();
        VulkanContext::CreateInfo info{};
        InitVulkanCreateInfoFromConfig(&info);
        if (!g_Vulkan->CreateInstanceAndDevice(info)) {
            NSLog(@"[PSPBridge] CreateInstanceAndDevice 失败");
            delete g_Vulkan; g_Vulkan = nullptr;
            state_ = VulkanCtxState::FAILED;
            return false;
        }
        g_Vulkan->SetCbGetDrawSize([]() {
            return VkExtent2D{(uint32_t)g_display.pixel_xres,
                              (uint32_t)g_display.pixel_yres};
        });
        state_ = VulkanCtxState::INITIALIZED;
        NSLog(@"[PSPBridge] Vulkan instance + device 创建成功");
        return true;
    }

    // Phase 2：渲染线程调用，绑定 CAMetalLayer，创建 swapchain
    bool InitFromRenderThread(CAMetalLayer *layer, int w, int h) {
        if (!g_Vulkan) return false;
        VkResult res = g_Vulkan->InitSurface(WINDOWSYSTEM_METAL_EXT,
                                              (__bridge void *)layer, nullptr);
        if (res != VK_SUCCESS) {
            NSLog(@"[PSPBridge] InitSurface 失败: %d", res);
            return false;
        }
        draw_ = Draw::T3DCreateVulkanContext(g_Vulkan, false);
        VkPresentModeKHR presentMode = ConfigPresentModeToVulkan(draw_);
        g_Vulkan->InitSwapchain(presentMode);
        SetGPUBackend(GPUBackend::VULKAN);
        draw_->CreatePresets();
        draw_->HandleEvent(Draw::Event::GOT_BACKBUFFER, w, h);
        VulkanRenderManager *rm = (VulkanRenderManager *)
            draw_->GetNativeObject(Draw::NativeObject::RENDER_MANAGER);
        rm->SetInflightFrames(g_Config.iInflightFrames);
        NSLog(@"[PSPBridge] Vulkan swapchain 初始化成功 %dx%d", w, h);
        return true;
    }

    void ShutdownFromRenderThread() override {
        if (draw_) {
            draw_->HandleEvent(Draw::Event::LOST_BACKBUFFER,
                               g_Vulkan->GetBackbufferWidth(),
                               g_Vulkan->GetBackbufferHeight());
            delete draw_; draw_ = nullptr;
        }
        if (g_Vulkan) {
            g_Vulkan->WaitUntilQueueIdle();
            g_Vulkan->PerformPendingDeletes();
            g_Vulkan->DestroySwapchain();
            g_Vulkan->DestroySurface();
        }
    }

    void Shutdown() override {
        if (g_Vulkan) {
            g_Vulkan->DestroyDevice();
            g_Vulkan->DestroyInstance();
        }
        finalize_glslang();
    }

    void Resize() override {}
    void *GetAPIContext() override { return g_Vulkan; }
    Draw::DrawContext *GetDrawContext() override { return draw_; }

    bool IsInitialized() const { return state_ == VulkanCtxState::INITIALIZED; }
    // ThreadStart/ThreadFrame/ThreadEnd 使用基类默认空实现
    // Vulkan 的渲染线程由 NativeFrame 内部管理

private:
    VulkanContext *g_Vulkan = nullptr;
    Draw::DrawContext *draw_ = nullptr;
    VulkanCtxState state_ = VulkanCtxState::PENDING;
};

// ─────────────────────────────────────────────────────────────────────────────
// 全局初始化标志
// ─────────────────────────────────────────────────────────────────────────────
static std::atomic<bool> g_ppssppGlobalInited{false};

static void InitPPSSPPGlobal() {
    if (g_ppssppGlobalInited.exchange(true)) return;
    g_threadManager.Init(cpu_info.num_cores, cpu_info.logical_cpu_count);

    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *ppssppDir = [docs stringByAppendingPathComponent:@"PPSSPP"];
    [[NSFileManager defaultManager] createDirectoryAtPath:ppssppDir
        withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *bundleAssets = [NSBundle mainBundle].resourcePath;
    NSString *ppssppAssets = [bundleAssets stringByAppendingPathComponent:@"ppsspp_assets"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:ppssppAssets]) {
        g_VFS.Register("", new DirectoryReader(Path(ppssppAssets.UTF8String)));
    }

    g_Config.iCpuCore              = (int)CPUCore::IR_INTERPRETER;
    g_Config.bSoftwareRendering    = false;   // 使用硬件渲染
    g_Config.iGPUBackend           = (int)GPUBackend::VULKAN;
    g_Config.iInternalResolution   = 2;       // 2x 分辨率（960x544）
    g_Config.bEnableSound          = true;
    g_Config.iAudioPlaybackMode    = 0;
    g_Config.bMemStickInserted     = true;
    g_Config.iMemStickSizeGB       = 16;
    g_Config.iFirmwareVersion      = 660;
    g_Config.iPSPModel             = 1;
    g_Config.bEnableLogging        = false;
    g_Config.bVertexDecoderJit     = true;
    g_Config.bSoftwareSkinning     = true;
    g_Config.iSplineBezierQuality  = 1;
    g_Config.bHighQualityDepth     = 1;
    g_Config.iButtonPreference     = 1;
    g_Config.iLockParentalLevel    = 9;
    g_Config.iGameVolume           = 10;
    g_Config.iReverbVolume         = 10;
    g_Config.iInflightFrames       = 2;
    g_Config.bRenderMultiThreading = true;

    g_Config.memStickDirectory     = Path(ppssppDir.UTF8String);
    g_Config.flash0Directory       = Path(ppssppDir.UTF8String) / "flash0";
    g_Config.internalDataDirectory = Path(ppssppDir.UTF8String);

    CreateSysDirectories();
}

// ─────────────────────────────────────────────────────────────────────────────
// PSPBridgeObjC 实现
// ─────────────────────────────────────────────────────────────────────────────
@implementation PSPBridgeObjC {
    std::vector<uint32_t>         _frameBuffer;   // 软件渲染帧缓冲
    std::vector<int16_t>          _audioBuffer;
    int                           _audioSamples;
    BOOL                          _romLoaded;
    BOOL                          _useVulkan;     // YES=Vulkan渲染，NO=软件渲染
    std::string                   _romPath;
    // Vulkan 上下文
    RetroEmuVulkanContext        *_vulkanCtx;
    // 渲染线程
    std::thread                   _renderThread;
    std::atomic<bool>             _renderThreadRunning;
    std::atomic<bool>             _exitRenderLoop;
    // 软件渲染双缓冲
    std::vector<uint32_t>         _pendingFrame;
    std::atomic<bool>             _newFrameReady;
    std::mutex                    _frameMutex;
}

@synthesize useJIT = _useJIT;
@synthesize metalLayer = _metalLayer;

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(PSP_NATIVE_WIDTH * PSP_NATIVE_HEIGHT, 0xFF000000);
        _pendingFrame.resize(PSP_NATIVE_WIDTH * PSP_NATIVE_HEIGHT, 0xFF000000);
        _audioBuffer.resize(PSP_SPF * 2 * 4, 0);
        _audioSamples        = 0;
        _romLoaded           = NO;
        _useVulkan           = NO;
        _useJIT              = NO;
        _vulkanCtx           = nullptr;
        _renderThreadRunning = false;
        _exitRenderLoop      = false;
        _newFrameReady       = false;
    }
    return self;
}

- (void)dealloc {
    [self shutdownPPSSPP];
}

- (void)setRenderScale:(NSInteger)scale { (void)scale; }

- (void)shutdownPPSSPP {
    if (_renderThreadRunning.load()) {
        _exitRenderLoop = true;
        if (_renderThread.joinable()) _renderThread.join();
        _renderThreadRunning = false;
    }
    if (_vulkanCtx) {
        if (_romLoaded) {
            PSP_Shutdown(true);
        }
        _vulkanCtx->Shutdown();
        delete _vulkanCtx;
        _vulkanCtx = nullptr;
    }
    _romLoaded = NO;
}

// ── ROM 加载 ────────────────────────────────────────────────────────────────
- (BOOL)loadROM:(NSData *)data filename:(NSString *)filename {
    if (data.length == 0) return NO;
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    if (![data writeToFile:tmpPath atomically:YES]) return NO;
    return [self loadROMFromPath:tmpPath];
}

- (BOOL)loadROMFromPath:(NSString *)path {
    if (!path || path.length == 0) return NO;
    if (!_metalLayer) {
        NSLog(@"[PSPBridge] ❌ metalLayer 未设置，无法初始化 Vulkan");
        return NO;
    }

    [self shutdownPPSSPP];
    InitPPSSPPGlobal();

    _romPath = path.UTF8String;
    PSPBridge_ClearAudio();

    // Phase 1：主线程初始化 Vulkan instance + device
    _vulkanCtx = new RetroEmuVulkanContext();
    if (!_vulkanCtx->InitAPI()) {
        NSLog(@"[PSPBridge] ❌ Vulkan InitAPI 失败，回退到软件渲染");
        delete _vulkanCtx; _vulkanCtx = nullptr;
        return [self loadROMSoftware:path];
    }
    // 设置 display 尺寸
    CGSize layerSize = _metalLayer.bounds.size;
    CGFloat scale    = _metalLayer.contentsScale;
    int pixW = (int)(layerSize.width  * scale);
    int pixH = (int)(layerSize.height * scale);
    if (pixW <= 0) pixW = 960;
    if (pixH <= 0) pixH = 544;
    g_display.pixel_xres = pixW;
    g_display.pixel_yres = pixH;
    g_display.dpi_scale_x = 1.0f;
    g_display.dpi_scale_y = 1.0f;

    // Phase 2 + 游戏启动在渲染线程里完成
    _exitRenderLoop      = false;
    _renderThreadRunning = true;
    _useVulkan           = YES;

    CAMetalLayer *layer = _metalLayer;
    std::string romPath = _romPath;

    _renderThread = std::thread([self, layer, romPath, pixW, pixH]() {
        SetCurrentThreadName("psp.vulkan");

        // Phase 2：绑定 Metal layer，创建 swapchain
        if (!_vulkanCtx->InitFromRenderThread(layer, pixW, pixH)) {
            NSLog(@"[PSPBridge] ❌ InitFromRenderThread 失败");
            _renderThreadRunning = false;
            return;
        }

        // 构造 CoreParameter
        CoreParameter coreParam;
        coreParam.cpuCore           = CPUCore::IR_INTERPRETER;
        coreParam.gpuCore           = GPUCORE_VULKAN;
        coreParam.graphicsContext   = _vulkanCtx;
        coreParam.enableSound       = true;
        coreParam.fileToStart       = Path(romPath);
        coreParam.startBreak        = false;
        coreParam.headLess          = false;
        coreParam.renderScaleFactor = 2;
        coreParam.renderWidth       = PSP_NATIVE_WIDTH  * 2;
        coreParam.renderHeight      = PSP_NATIVE_HEIGHT * 2;
        coreParam.pixelWidth        = pixW;
        coreParam.pixelHeight       = pixH;

        if (!PSP_InitStart(coreParam)) {
            NSLog(@"[PSPBridge] ❌ PSP_InitStart 失败");
            _vulkanCtx->ShutdownFromRenderThread();
            _renderThreadRunning = false;
            return;
        }

        // 等待启动完成
        std::string errorStr;
        for (int i = 0; i < 300 && !_exitRenderLoop.load(); i++) {
            BootState state = PSP_InitUpdate(&errorStr);
            if (state == BootState::Complete) break;
            if (state == BootState::Failed) {
                NSLog(@"[PSPBridge] ❌ 启动失败: %s", errorStr.c_str());
                _vulkanCtx->ShutdownFromRenderThread();
                _renderThreadRunning = false;
                return;
            }
            usleep(100000);  // 100ms
        }

        if (!PSP_IsInited()) {
            NSLog(@"[PSPBridge] ❌ 启动超时");
            _vulkanCtx->ShutdownFromRenderThread();
            _renderThreadRunning = false;
            return;
        }

        UpdateUIState(UISTATE_INGAME);
        System_Notify(SystemNotification::BOOT_DONE);
        _romLoaded = YES;
        NSLog(@"[PSPBridge] ✅ Vulkan 渲染启动成功");

        // 初始化 GPU（Vulkan 后端）
        Draw::DrawContext *draw = _vulkanCtx->GetDrawContext();
        if (!GPU_Init(GPUCORE_VULKAN, _vulkanCtx, draw)) {
            NSLog(@"[PSPBridge] ❌ GPU_Init 失败");
            _vulkanCtx->ShutdownFromRenderThread();
            _renderThreadRunning = false;
            return;
        }
        Core_SetGraphicsContext(_vulkanCtx);

        // 主渲染循环
        static const int BLOCK_CYCLES = (int)(222000000.0 / 1000.0);  // 1ms
        while (!_exitRenderLoop.load()) {
            // 开始帧
            if (gpu) {
                gpu->BeginHostFrame(g_Config.GetDisplayLayoutConfig(DeviceOrientation::Landscape));
            }
            if (draw) {
                draw->BeginFrame(Draw::DebugFlags::NONE);
            }

            // 运行 CPU 直到 CORE_NEXTFRAME
            coreState = CORE_RUNNING_CPU;
            for (int i = 0; i < 100 && !_exitRenderLoop.load(); i++) {
                PSP_RunLoopFor(BLOCK_CYCLES);
                if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN) break;
            }
            if (coreState == CORE_NEXTFRAME) coreState = CORE_RUNNING_CPU;
            else if (coreState == CORE_POWERDOWN) {
                if (draw) draw->EndFrame();
                if (gpu) gpu->EndHostFrame();
                break;
            }

            // 结束帧（触发 Vulkan present）
            if (gpu) gpu->EndHostFrame();
            if (draw) draw->EndFrame();
        }

        NSLog(@"[PSPBridge] 渲染循环退出");
        GPU_Shutdown();
        _vulkanCtx->ShutdownFromRenderThread();
        PSP_Shutdown(true);
        _romLoaded = NO;
        _renderThreadRunning = false;
    });

    // 等待 ROM 加载完成（最多 35 秒）
    for (int i = 0; i < 350 && !_romLoaded && _renderThreadRunning.load(); i++) {
        usleep(100000);
    }

    return _romLoaded;
}

// ── 软件渲染回退（Vulkan 不可用时）────────────────────────────────────────
- (BOOL)loadROMSoftware:(NSString *)path {
    NSLog(@"[PSPBridge] 使用软件渲染回退");
    g_Config.bSoftwareRendering    = true;
    g_Config.bSoftwareRenderingJit = true;
    g_Config.iGPUBackend           = (int)GPUBackend::VULKAN;  // 不影响软件渲染

    CoreParameter coreParam;
    coreParam.cpuCore           = CPUCore::IR_INTERPRETER;
    coreParam.gpuCore           = GPUCORE_SOFTWARE;
    coreParam.graphicsContext   = nullptr;
    coreParam.enableSound       = true;
    coreParam.fileToStart       = Path(path.UTF8String);
    coreParam.startBreak        = false;
    coreParam.headLess          = false;
    coreParam.renderScaleFactor = 1;
    coreParam.renderWidth       = PSP_NATIVE_WIDTH;
    coreParam.renderHeight      = PSP_NATIVE_HEIGHT;
    coreParam.pixelWidth        = PSP_NATIVE_WIDTH;
    coreParam.pixelHeight       = PSP_NATIVE_HEIGHT;

    if (!PSP_InitStart(coreParam)) return NO;

    std::string errorStr;
    for (int i = 0; i < 300; i++) {
        BootState state = PSP_InitUpdate(&errorStr);
        if (state == BootState::Complete) break;
        if (state == BootState::Failed) return NO;
        usleep(100000);
    }
    if (!PSP_IsInited()) return NO;

    UpdateUIState(UISTATE_INGAME);
    System_Notify(SystemNotification::BOOT_DONE);

    _renderThreadRunning = true;
    _exitRenderLoop      = false;
    _useVulkan           = NO;
    _newFrameReady       = false;

    _renderThread = std::thread([self]() {
        SetCurrentThreadName("psp.sw");
        static const int BLOCK = (int)(222000000.0 / 1000.0);
        static const double FRAME_TIME = 1.0 / 60.0;
        _romLoaded = YES;
        while (!_exitRenderLoop.load()) {
            double frameStart = time_now_d();
            coreState = CORE_RUNNING_CPU;
            for (int i = 0; i < 100 && !_exitRenderLoop.load(); i++) {
                PSP_RunLoopFor(BLOCK);
                if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN) break;
            }
            if (coreState == CORE_NEXTFRAME) {
                coreState = CORE_RUNNING_CPU;
                // 读取软件渲染帧缓冲
                if (gpuDebug) {
                    GPUDebugBuffer buf;
                    if (gpuDebug->GetCurrentFramebuffer(buf, GPU_DBG_FRAMEBUF_DISPLAY)) {
                        const u8 *src = buf.GetData();
                        u32 stride = buf.GetStride();
                        u32 height = buf.GetHeight();
                        GPUDebugBufferFormat fmt = buf.GetFormat();
                        if (src && stride > 0 && height > 0) {
                            int copyH = (int)std::min((u32)PSP_NATIVE_HEIGHT, height);
                            std::lock_guard<std::mutex> lock(_frameMutex);
                            if (fmt == GPU_DBG_FORMAT_8888) {
                                for (int y = 0; y < copyH; y++) {
                                    const uint32_t *s = (const uint32_t *)(src + y * stride * 4);
                                    memcpy(_pendingFrame.data() + y * PSP_NATIVE_WIDTH, s, PSP_NATIVE_WIDTH * 4);
                                }
                            } else if (fmt == GPU_DBG_FORMAT_8888_BGRA) {
                                for (int y = 0; y < copyH; y++) {
                                    const uint32_t *s = (const uint32_t *)(src + y * stride * 4);
                                    uint32_t *d = _pendingFrame.data() + y * PSP_NATIVE_WIDTH;
                                    for (int x = 0; x < PSP_NATIVE_WIDTH; x++) {
                                        uint32_t p = s[x];
                                        d[x] = 0xFF000000 | ((p & 0xFF0000) >> 16) | (p & 0xFF00) | ((p & 0xFF) << 16);
                                    }
                                }
                            } else if (fmt == GPU_DBG_FORMAT_565) {
                                for (int y = 0; y < copyH; y++) {
                                    const uint16_t *s = (const uint16_t *)(src + y * stride * 2);
                                    uint32_t *d = _pendingFrame.data() + y * PSP_NATIVE_WIDTH;
                                    for (int x = 0; x < PSP_NATIVE_WIDTH; x++) {
                                        uint16_t p = s[x];
                                        d[x] = 0xFF000000 | (((p >> 11) & 0x1F) * 255 / 31)
                                             | ((((p >> 5) & 0x3F) * 255 / 63) << 8)
                                             | (((p & 0x1F) * 255 / 31) << 16);
                                    }
                                }
                            }
                            _newFrameReady = true;
                        }
                    }
                }
            } else if (coreState == CORE_POWERDOWN) {
                break;
            }
            // 帧率限制：软件渲染不超过 60fps
            double elapsed = time_now_d() - frameStart;
            if (elapsed < FRAME_TIME) {
                usleep((useconds_t)((FRAME_TIME - elapsed) * 1e6));
            }
        }
        _romLoaded = NO;
        _renderThreadRunning = false;
    });

    for (int i = 0; i < 50 && !_romLoaded; i++) usleep(100000);
    return _romLoaded;
}

// ── 每帧（主线程）──────────────────────────────────────────────────────────
- (void)runFrame {
    if (!_romLoaded) return;

    // 软件渲染：把 pendingFrame 拷贝到 frameBuffer
    if (!_useVulkan && _newFrameReady.load()) {
        std::lock_guard<std::mutex> lock(_frameMutex);
        memcpy(_frameBuffer.data(), _pendingFrame.data(),
               PSP_NATIVE_WIDTH * PSP_NATIVE_HEIGHT * sizeof(uint32_t));
        _newFrameReady = false;
    }

    // 读取音频
    std::lock_guard<std::mutex> lock(g_audioBufMutex);
    int avail = g_audioAvail;
    int take  = std::min(avail, (int)_audioBuffer.size());
    take &= ~1;
    if (take > 0) {
        for (int i = 0; i < take; i++) {
            _audioBuffer[i] = g_audioRing[g_audioRead];
            g_audioRead = (g_audioRead + 1) % AUDIO_RING_CAP;
        }
        g_audioAvail -= take;
        _audioSamples = take;
    } else {
        _audioSamples = 0;
    }
}

- (void)reset {
    if (!_romPath.empty()) {
        NSString *path = [NSString stringWithUTF8String:_romPath.c_str()];
        [self loadROMFromPath:path];
    }
}

// Vulkan 模式返回 nil（画面在 metalLayer），软件渲染返回帧缓冲
- (const uint32_t *)getFrameBuffer {
    return _useVulkan ? nullptr : _frameBuffer.data();
}
- (NSInteger)frameWidth            { return PSP_NATIVE_WIDTH; }
- (NSInteger)frameHeight           { return PSP_NATIVE_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    if (!_romLoaded) return;
    uint32_t set = 0, clear = 0;
    if (buttons & (1 << 0))  set |= PSP_CTRL_CROSS;    else clear |= PSP_CTRL_CROSS;
    if (buttons & (1 << 1))  set |= PSP_CTRL_CIRCLE;   else clear |= PSP_CTRL_CIRCLE;
    if (buttons & (1 << 2))  set |= PSP_CTRL_SELECT;   else clear |= PSP_CTRL_SELECT;
    if (buttons & (1 << 3))  set |= PSP_CTRL_START;    else clear |= PSP_CTRL_START;
    if (buttons & (1 << 4))  set |= PSP_CTRL_UP;       else clear |= PSP_CTRL_UP;
    if (buttons & (1 << 5))  set |= PSP_CTRL_DOWN;     else clear |= PSP_CTRL_DOWN;
    if (buttons & (1 << 6))  set |= PSP_CTRL_LEFT;     else clear |= PSP_CTRL_LEFT;
    if (buttons & (1 << 7))  set |= PSP_CTRL_RIGHT;    else clear |= PSP_CTRL_RIGHT;
    if (buttons & (1 << 8))  set |= PSP_CTRL_SQUARE;   else clear |= PSP_CTRL_SQUARE;
    if (buttons & (1 << 9))  set |= PSP_CTRL_TRIANGLE; else clear |= PSP_CTRL_TRIANGLE;
    if (buttons & (1 << 10)) set |= PSP_CTRL_LTRIGGER; else clear |= PSP_CTRL_LTRIGGER;
    if (buttons & (1 << 11)) set |= PSP_CTRL_RTRIGGER; else clear |= PSP_CTRL_RTRIGGER;
    __CtrlUpdateButtons(set, clear);
}

- (void)setPlayer2Buttons:(uint16_t)buttons { (void)buttons; }

- (const int16_t *)getAudioBuffer { return _audioSamples > 0 ? _audioBuffer.data() : nullptr; }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return PSP_SAMPLE_RATE; }

- (nullable NSData *)saveState { return nil; }
- (BOOL)loadState:(NSData *)data { (void)data; return NO; }
- (void)writeByte:(uint8_t)value at:(uint32_t)address { (void)value; (void)address; }

@end
