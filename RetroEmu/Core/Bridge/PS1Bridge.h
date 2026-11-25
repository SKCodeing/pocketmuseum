// PS1Bridge.h
// PCSX-ReARMed PlayStation 核心桥接头文件
// Sprint 6: PS1 平台支持
//
// 需要 PS1 BIOS 文件（SCPH1001.BIN），放置于 Documents/BIOS/ 目录
// 支持格式：.bin/.cue, .iso, .pbp

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PS1BridgeObjC : NSObject

- (BOOL)loadROM:(NSData *)data;
- (void)runFrame;
- (void)reset;
- (const uint32_t * _Nullable)getFrameBuffer;
- (NSInteger)frameWidth;
- (NSInteger)frameHeight;
- (void)setPlayer1Buttons:(uint16_t)buttons;
- (void)setPlayer2Buttons:(uint16_t)buttons;
- (const int16_t * _Nullable)getAudioBuffer;
- (NSInteger)audioSampleCount;
- (NSInteger)sampleRate;
- (nullable NSData *)saveState;
- (BOOL)loadState:(NSData *)data;
- (void)writeByte:(uint8_t)value at:(uint32_t)address;

/// 加载 PS1 BIOS（必须在 loadROM 前调用）
- (BOOL)loadBIOS:(NSData *)biosData;

@end

NS_ASSUME_NONNULL_END
