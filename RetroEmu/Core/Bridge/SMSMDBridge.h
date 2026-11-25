// SMSMDBridge.h
// Genesis-Plus-GX SMS / Mega Drive / Sega 32X / Sega CD 桥接头文件
// PE-1: 扩展支持 32X 和 Sega CD（GenesisPlus GX 内置支持）

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SMSMDSystemType) {
    SMSMDSystemTypeSMS    = 0,
    SMSMDSystemTypeMD     = 1,
    SMSMDSystemTypeSega32X = 2,   // PE-1: Sega 32X
    SMSMDSystemTypeSegaCD  = 3,   // PE-1: Sega CD / Mega-CD
} NS_SWIFT_NAME(SMSMDSystemType);

NS_ASSUME_NONNULL_BEGIN

@interface SMSMDBridgeObjC : NSObject

- (instancetype)initWithSystem:(SMSMDSystemType)system;

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

/// Sega CD：加载 BIOS 文件（需在 Documents 目录放置 bios_CD_U.bin）
- (BOOL)loadBIOS:(NSData *)biosData;

@end

NS_ASSUME_NONNULL_END
