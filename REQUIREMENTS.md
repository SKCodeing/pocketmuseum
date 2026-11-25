# RetroEmu 功能需求文档

## 已实现功能

### 核心模拟器
- **12 个平台**：NES / GBC / GG / SMS / MD / GBA / SNES / NDS / 32X / MCD / N64 / PS1
  - NES/GBC/GG/SMS/MD/GBA：真实核心已集成（Nestopia / Gambatte / SMSPlus / GenesisPlus / mGBA）
  - SNES/NDS：桥接层完成，核心库待 `build_snes9x.sh` / `build_melonds.sh`
  - 32X/MCD：GenesisPlus GX 扩展，桥接层完成
  - N64/PS1：桥接层完成，核心库待 `build_mupen64plus.sh` / `build_pcsx.sh`
- Metal 渲染管线，7 种滤镜（像素风 / 清晰增强 / LCD 格子 / CRT / 扫描线 / NTSC / 高清重制）
- 环形缓冲区音频引擎（AVAudioEngine 拉取模式）
- 手动存档（无限槽位）+ 自动即时存档（最多 50 条，可配置间隔）
- 存档槽截图预览
- 存档导出/备份（ZIP 打包，分享到 Files）
- 倒带/回放（RewindManager，环形缓冲 300 帧，按住快捷键倒带）
- 宏录制（MacroManager，RLE 压缩，单次/循环回放）

### 输入
- 虚拟手柄（DPad + ABXY + START/SEL），支持布局编辑（拖拽/缩放/透明度）
- MFi / DualShock 4&5 / Xbox / Switch Pro / Joy-Con（GamepadManager，最多 4 个同时接入）
- 按键重映射 + 自定义快捷键（截图/快进/存档/读档/菜单/倒带）
- Turbo 连发 / 触觉反馈 / 陀螺仪（GBA）
- 第三方皮肤支持（自有 `.retroskin` 格式）
- 双指快捷手势（上存档 / 下读档 / 左快进 / 右截图）

### 游戏列表
- 标签页分类（全部 / 最近 / 收藏 / 按系统 / 自定义标签）
- 游戏标签分组（GameTagManager，内置3个+自定义，拖拽排序）
- 搜索过滤 / 封面图 / 游玩时长统计 / 收藏管理

### 网络与导入
- 局域网多人（Bonjour + TCP 帧同步）
- WiFi ROM 传输（HTTP 服务器 + Web UI）
- WebDAV 云端导入（Nextcloud / 群晖 NAS 等）
- 从其他 App 直接打开 ROM（文件关联）

### 显示
- AirPlay 投屏（游戏画面输出到外部屏幕，手机作为控制器）

### 成就
- RetroAchievements.org 集成（账号登录、成就列表、解锁弹窗、30 秒服务器轮询）

### 系统集成
- Spotlight 搜索（SpotlightManager，ROM 导入/删除自动同步索引）
- 主屏幕 Widget（RetroEmuWidget，小/中/大三种尺寸，App Group 共享数据）
- retroemu:// URL scheme（Widget / Spotlight deep link）

### 其他
- ZIP 解压导入
- 作弊码（Game Genie / GameShark / Raw Address）
- 快进模式（1x / 2x / 4x / 8x）
- 音量控制 / 外观主题 / 截图水印
- 设置页面（含所有功能入口）

---

## 待开发

### 互联网联机
- WebSocket 中继服务器（需配套后端）

### PSP（PPSSPP）
- 需要 JIT，iOS 不允许，等待 Apple 政策变化

### 云存储扩展
- Dropbox / Google Drive OAuth（需各自开发者账号）
- 百度云 / 阿里云（国内用户专项）

---

## 技术债务

| 问题 | 状态 |
|------|------|
| `GamepadView` MFi 逻辑与 `GamepadManager` 重叠 | ✅ Sprint 4 已修复 |
| `CoverArtManager` 下载失败无重试 | ✅ Sprint 4 已修复（指数退避，最多3次）|
| Metal shader 无 fallback | ✅ Sprint 4 已修复（软件渲染降级）|
| `AchievementManager` 内存轮询未完整实现 | ✅ Sprint 4 已修复（服务器轮询版）|
| `EmulatorViewController.showMenu()` 菜单项较多 | 待优化 |
| `NetworkManager` 仅支持 2 人 | 待扩展到 4 人 |
| rcheevos C 库集成（本地内存条件检测） | 长期 |
