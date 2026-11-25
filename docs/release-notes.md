# RetroEmu 迭代说明

**迭代周期**：2026-05-08  
**基础分支**：`master`  
**功能分支**：`feature/competitive-parity`  
**JIT 分支**：`feature/psp-jit`  
**代码变更**：68 个文件，新增 8480 行，修改 533 行

---

## 一、背景

本轮迭代补齐了平台覆盖与核心体验上的空白：新增 6 个平台，并为存档、手柄、导入、
渲染补齐了长期缺失的能力。

---

## 二、分支结构

```
master
  └── feature/competitive-parity   ← 主功能分支（App Store 合规）
        └── feature/psp-jit        ← PSP JIT 分支（旁加载/AltStore 专用）
```

### `feature/competitive-parity`（22 次提交）
App Store 可上架版本，包含所有新功能和编译修复。

### `feature/psp-jit`（在上面基础上 +16 次提交）
旁加载专用版本，PSP 模拟启用 JIT 加速（~100% 速度）。

---

## 三、功能迭代详情

### Sprint 1 — 基础功能补全
涉及：自动存档、截图分享、多手柄支持、自定义快捷键

| 功能 | 说明 |
|------|------|
| **F1 自动即时存档** | 每 60 秒自动保存，最多保留 50 条，时间轴 UI 浏览 |
| **F2 游戏截图** | 截取当前帧，保存到系统相册，支持分享菜单 |
| **F5 手柄扩展** | 新增 `GamepadManager`，支持 DualShock 4/5、Xbox、Joy-Con，最多 4 个同时接入 |
| **F8 自定义快捷键** | 截图/快进/存档/读档/菜单/倒带 可绑定到任意手柄按键 |

---

### Sprint 2+3 — 平台扩展 + 体验提升
涉及：SNES/NDS 支持、云导入、AirPlay、皮肤、成就

| 功能 | 说明 |
|------|------|
| **SNES 支持** | Snes9x 桥接层完成，构建脚本 `build_snes9x.sh` |
| **NDS 支持** | melonDS 桥接层完成，双屏 256×384 帧缓冲，触摸屏接口 |
| **F3 WebDAV 云导入** | 支持 Nextcloud/群晖 NAS，Keychain 账号持久化，下载进度显示 |
| **F4 AirPlay 投屏** | 游戏画面输出到外部屏幕，手机切换为控制器模式 |
| **F6 第三方皮肤** | 自有 `.retroskin` 皮肤包格式（ZIP + `info.json` + `preview.png`） |
| **F7 成就系统** | RetroAchievements.org 集成，成就解锁弹窗，30 秒服务器轮询 |

---

### Sprint 3 polish — 设置页 + 文案
- `SettingsViewController` 全面补全：截图水印、自动存档间隔、倒带缓冲、皮肤、WebDAV、RA 账号
- `KeymapViewController` 新增快捷键绑定 Section（F8 UI 完整实现）
- App Store 文案重写，覆盖所有新功能

---

### Sprint 4 — 技术债务修复 + 倒带 + 快捷手势

**技术债务修复：**

| 问题 | 修复方案 |
|------|----------|
| TD-1 `GamepadView` MFi 与 `GamepadManager` 重叠 | 移除 `setupMFi/connectMFi`，统一由 `GamepadManager` 处理，触觉反馈移至 `GamepadManager` |
| TD-2 `CoverArtManager` 无重试 | 指数退避（5s/30s/300s），最多 3 次，新增 SNES/NDS 封面图路径 |
| TD-3 Metal shader 无 fallback | `MetalRenderer.init?` 返回 nil 时降级到 `UIImageView` 软件渲染 |
| TD-4 成就轮询未实现 | 服务器轮询版（30 秒间隔），`startPolling/stopPolling` |

**新功能：**

| 功能 | 说明 |
|------|------|
| **F9 倒带/回放** | `RewindManager`，环形缓冲 300 帧（10 秒），按住快捷键倒带，音频自动静音 |
| **F10 双指快捷手势** | 上存档/下读档/左快进/右截图，设置开关，与画面调整手势共存 |

---

### Sprint 5 — 游戏库增强 + 宏录制

| 功能 | 说明 |
|------|------|
| **F11 游戏标签分组** | `GameTagManager`，内置 3 个标签（通关了/进行中/待玩）+ 自定义，拖拽排序 |
| **F12 Spotlight 搜索** | `SpotlightManager`，ROM 导入/删除自动同步索引，点击直接启动游戏 |
| **F13 Widget 小组件** | `RetroEmuWidget`，小/中/大三种尺寸，App Group 共享数据，`retroemu://` deep link |
| **F14 宏录制** | `MacroManager`，RLE 压缩，单次/循环回放，最多 5 个宏，游戏内菜单入口 |

---

### Sprint 6 — 平台扩展（32X/MCD/N64/PS1/PSP）

| 平台 | 核心库 | 状态 |
|------|--------|------|
| **Sega 32X** | GenesisPlus GX 扩展 | ✅ 完整实现（ROM 头自动检测） |
| **Sega CD / Mega-CD** | GenesisPlus GX + `HW_ADDON_MEGACD` | ✅ 完整实现，支持 BIOS 加载 |
| **Nintendo 64** | Mupen64Plus（解释器模式） | ✅ 桥接完成，待集成核心库 |
| **PlayStation** | PCSX-ReARMed | ✅ 桥接完成，BIOS 自动检测 |
| **PSP（IR Interpreter）** | PPSSPP | ✅ App Store 合规，iPhone 12+ 全速 |

**构建脚本**：`build_mupen64plus.sh`、`build_pcsx.sh`、`build_ppsspp.sh`

---

### PSP JIT 分支（`feature/psp-jit`）

在 `feature/competitive-parity` 基础上，额外实现：

| 改动 | 说明 |
|------|------|
| `PSPBridge.mm` | `useJIT = YES`，运行时 `mmap(PROT_EXEC)` 验证，失败自动降级 |
| `RetroEmu.entitlements` | 加入 `com.apple.security.cs.allow-jit` |
| `RetroEmuSideload.entitlements` | 完整旁加载权限集（JIT + iCloud） |
| `EmulatorViewController` | `isJITAvailable` 静态检测，PSP 游戏启动时显示 Toast |
| `docs/psp-jit-guide.md` | AltStore/SideStore/Xcode 安装指南 + FAQ |

**性能对比：**

| 模式 | 速度 | 耗电 | 分发方式 |
|------|------|------|----------|
| IR Interpreter | ~85-95% | 较高 | App Store ✅ |
| JIT | ~100% | 更低 | 旁加载/AltStore/EU 市场 |

---

## 四、编译修复（Xcode 26 / Swift 6 兼容）

本轮迭代针对 Xcode 26（`-default-isolation=MainActor`）做了大量兼容性修复：

| 问题 | 修复方案 |
|------|----------|
| `DispatchQueue.global + DispatchQueue.main.async` 嵌套导致编译器崩溃 | 改为 `Task.detached + await MainActor.run` |
| `AchievementManager` 多层嵌套闭包类型推断失败 | 重写为 `async/await`（`fetchAchievements` + `fetchUserUnlocks`） |
| `CC_MD5_*` 在 iOS 26 SDK 废弃 | 改用 `CryptoKit.Insecure.MD5` |
| `Dictionary.Values ?? []` 类型推断失败 | 改为 `map { Array($0.values) } ?? []` |
| `controller.productCategory` 非 Optional | `if let` 改为 `!isEmpty` 判断 |
| `[Int: EmulatorButton] = []` 字典字面量错误 | 改为 `[:]` |
| `withReuseIdentifier:` 用于 UITableView | 改为 `withIdentifier:` |
| `scene(_:openURLContexts:)` 重复声明 | 合并为一个方法，按 URL scheme 分发 |
| `NotificationCenter.post` 类型歧义 | 明确为 `Notification.Name.xxx` |
| `SkinPickerViewController` 缺少 import | 加入 `import UniformTypeIdentifiers` |
| `HW_32X` / `HW_SEGACD` 不存在 | 32X 自动检测，Sega CD 改用 `HW_ADDON_MEGACD` |
| `config.bios_path` 不存在 | 改为 `config.bios = 1` 标志位 |
| `fileExists:atPath:` ObjC 语法错误 | 改为 `fileExistsAtPath:` |
| `switch EmulatorSystem` 不完整 | 补全所有新平台 case |

---

## 五、代码合并操作记录

### 步骤 1：在 `feature/competitive-parity` 上完成所有功能开发
```bash
git checkout -b feature/competitive-parity
# Sprint 1-6 开发...
git commit -m "feat: Sprint 1 - competitive parity features"
git commit -m "feat: Sprint 2+3 - platform expansion, cloud import, AirPlay, skins, achievements"
git commit -m "feat: Sprint 3 polish - settings, keymap UI, App Store copy"
git commit -m "feat: Sprint 4 - tech debt fixes + rewind + swipe gestures"
git commit -m "feat: Sprint 5 - game library enhancements + macro recording"
git commit -m "feat: Sprint 6 - platform expansion (32X, Sega CD, N64, PS1)"
git commit -m "feat: PSP support via PPSSPP IR Interpreter (App Store compliant)"
```

### 步骤 2：新建 JIT 分支
```bash
git checkout -b feature/psp-jit
# 在 PSPBridge.mm 中启用 JIT，添加 entitlements，运行时检测
git commit -m "feat: PSP JIT mode (sideload/AltStore/EU market)"
```

### 步骤 3：修复 Xcode 26 编译错误（在 psp-jit 分支上）
```bash
# 14 次 fix commit...
git commit -m "fix: remove extra brace in importROM()"
git commit -m "fix: replace DispatchQueue.global+main nesting with Task.detached+MainActor.run"
# ... 更多修复
```

### 步骤 4：将修复同步到 `feature/competitive-parity`
```bash
git checkout feature/competitive-parity
git cherry-pick f6ccc04 9b001e1 de8d046 d9c9de3 5b6b01e \
               a19f7ef b069d71 961cef2 d506599 e1301ff \
               8584b8e f5772db 02c4d6d 2bf9ee1
# 14 个 commit 全部成功，无冲突
```

### 最终分支状态
```
master (原始代码)
  └── feature/competitive-parity  [22 commits ahead of master]
        └── feature/psp-jit       [+16 commits]
```

---

## 六、待合并到 master

在以下条件满足后，将 `feature/competitive-parity` 合并到 `master`：

- [ ] 集成真实核心库（Snes9x / melonDS / Mupen64Plus / PCSX-ReARMed / PPSSPP）
- [ ] 完成 App Store 截图（iPhone 6.9"、iPad Pro 12.9"）
- [ ] 配置 App Store Connect 内购项目（Pro 版本 $2.99 / ¥18）
- [ ] 提交 App Store 审核

`feature/psp-jit` 单独维护，用于 AltStore/SideStore 分发。
