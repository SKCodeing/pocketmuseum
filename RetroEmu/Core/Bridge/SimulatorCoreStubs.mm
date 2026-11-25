// SimulatorCoreStubs.mm
// 模拟器构建下 SNES / NDS / N64 / PS1 四个核心的替身实现。
//
// 这几个核心的静态库目前只有真机 arm64 切片，模拟器链接不到，
// 因此模拟器构建用 EXCLUDED_SOURCE_FILE_NAMES 把真实桥接排除掉，
// 由这里提供同名的空实现，保证 Swift 层的 Wrapper 仍可编译、可实例化，
// 只是 loadROM 直接返回失败。真机构建不编译本文件的内容。

#import <Foundation/Foundation.h>
#import "RetroEmuConfig.h"
#import "SNESBridge.h"
#import "NDSBridge.h"
#import "N64Bridge.h"
#import "PS1Bridge.h"

#if TARGET_OS_SIMULATOR

static const NSInteger kStubSampleRate = 32000;

#define RT_SIM_STUB_IMPLEMENTATION(className, width, height)                       \
@implementation className                                                             \
- (BOOL)loadROM:(NSData *)data {                                                   \
    NSLog(@"[RetroEmu] %@ 在模拟器下不可用：该核心只有真机切片", NSStringFromClass([self class])); \
    return NO;                                                                     \
}                                                                                  \
- (void)runFrame {}                                                                \
- (void)reset {}                                                                   \
- (const uint32_t *)getFrameBuffer { return NULL; }                                \
- (NSInteger)frameWidth { return (width); }                                        \
- (NSInteger)frameHeight { return (height); }                                      \
- (void)setPlayer1Buttons:(uint16_t)buttons {}                                     \
- (void)setPlayer2Buttons:(uint16_t)buttons {}                                     \
- (const int16_t *)getAudioBuffer { return NULL; }                                 \
- (NSInteger)audioSampleCount { return 0; }                                        \
- (NSInteger)sampleRate { return kStubSampleRate; }                                \
- (NSData *)saveState { return nil; }                                              \
- (BOOL)loadState:(NSData *)data { return NO; }                                    \
- (void)writeByte:(uint8_t)value at:(uint32_t)address {}                           \
@end

RT_SIM_STUB_IMPLEMENTATION(SNESBridgeObjC, 256, 224)
RT_SIM_STUB_IMPLEMENTATION(N64BridgeObjC, 320, 240)
RT_SIM_STUB_IMPLEMENTATION(NDSBridgeObjC, 256, 384)

@implementation NDSBridgeObjC (SimulatorTouch)
- (void)touchScreenAt:(float)x y:(float)y {}
- (void)touchScreenRelease {}
@end

@implementation PS1BridgeObjC
- (BOOL)loadROM:(NSData *)data {
    NSLog(@"[RetroEmu] PS1BridgeObjC 在模拟器下不可用：该核心只有真机切片");
    return NO;
}
- (void)runFrame {}
- (void)reset {}
- (const uint32_t *)getFrameBuffer { return NULL; }
- (NSInteger)frameWidth { return 320; }
- (NSInteger)frameHeight { return 240; }
- (void)setPlayer1Buttons:(uint16_t)buttons {}
- (void)setPlayer2Buttons:(uint16_t)buttons {}
- (const int16_t *)getAudioBuffer { return NULL; }
- (NSInteger)audioSampleCount { return 0; }
- (NSInteger)sampleRate { return 44100; }
- (NSData *)saveState { return nil; }
- (BOOL)loadState:(NSData *)data { return NO; }
- (void)writeByte:(uint8_t)value at:(uint32_t)address {}
- (BOOL)loadBIOS:(NSData *)biosData { return NO; }
@end

#endif
