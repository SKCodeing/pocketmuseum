// SNESBridge.h
// Snes9x Super Nintendo 核心桥接头文件
// Sprint 2: SNES 平台支持

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNESBridgeObjC : NSObject

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

@end

NS_ASSUME_NONNULL_END
