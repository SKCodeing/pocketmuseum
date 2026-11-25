# Pocket Museum / 掌机时光机

一座装进口袋的复古掌机博物馆：把游戏库当作一排展柜陈列，每次游玩留下的存档变成可回溯的时间轴。

> ### 存档状态
>
> 本项目已停止开发，**不再接受功能请求或 PR**，代码按原样保留。
>
> 它曾以「掌机时光机 / Pocket Museum」提交 App Store 审核，因 Guideline 4.3(a)（Spam）
> 被拒——Apple 认为这个多平台模拟器与商店里已有的同类 App 差异不足。重做界面、
> 更名、补原创功能都试过，判定没有改变，于是放弃上架，转为开源存档。
>
> 如果你只是想把代码读一读，这三处最值得看：
>
> - [`RetroEmu/Design/RetroDesignSystem.swift`](RetroEmu/Design/RetroDesignSystem.swift)
>   —— 全手写的 UIKit 设计系统（1246 行），调色、字阶、卡片、胶囊、浮动岛 Tab Bar
> - [`RetroEmu/Core/Bridge/`](RetroEmu/Core/Bridge/)
>   —— 十个模拟核心的 Objective-C++ 桥接层，以及各核心缺失符号的桩实现
> - [`Tools/testrom/build_demo_rom.py`](Tools/testrom/build_demo_rom.py)
>   —— 自己写的 6502 汇编器，用来生成内置那张 NES 卡带
>
> **提醒：本项目构建产物不能商业分发**，原因见
> [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 这是什么

一个 iOS 上的多平台复古游戏运行器，前端用 Swift + UIKit 全手写，渲染走 Metal，
后端通过 Objective-C++ 桥接层对接十个开源模拟器核心。

界面上刻意避开了"文件管理器 + 手柄"的常规形态，做成了博物馆的隐喻：

| 页面 | 内容 |
|---|---|
| 掌机柜 | 按平台陈列的展柜，而不是文件列表 |
| 展签 | 每张卡带的入藏编号、平台档案（iNES 分区 / mapper / CRC32）、策展笔记 |
| 时光 | 跨游戏的存档时间轴，自动存档与手动存档分列 |
| 年报 | 年内到馆时长、到场天数、最常重开的卡带，可导出长图 |
| 皮肤 | 自有 `.retroskin` 包格式（ZIP + `info.json` + `preview.png`） |

启动时有一段卡带入仓动画，遵守"减弱动态效果"。

## 目录

```
RetroEmu/            应用层（Swift + UIKit，MIT）
  Design/            设计系统 RT 令牌、启动动画、策展导览
  UI/                各页面控制器
  Core/Bridge/       十个核心的 Objective-C++ 桥接层与各核心缺失符号的桩实现
  Core/build_*.sh    各核心的静态库编译脚本
  Skin/  Input/  Museum/  Cheat/  Achievements/  CloudImport/  Transfer/
RetroEmuWidget/      主屏小组件
RetroEmuTests/       XCTest
RetroEmuUITests/     UI 测试 + 截图用例
Tools/testrom/       原创 NES 示例卡带的离线工具链（Python 6502 汇编器 + CHR 绘制）
Tools/AppIcon/       程序化生成 1024 图标
Scripts/             商店截图抓取脚本
docs/                迭代记录与发布说明
```

## 构建

**前提：本仓库不含模拟器核心**，需要先自行获取并编译。原因见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)——几个核心的许可证互相冲突，
不可能放进同一个 MIT 仓库。

```bash
# 1. 拉取核心源码到仓库根目录对应位置（目录名必须一致）
git clone https://github.com/libretro/nestopia.git            Nestopia
git clone https://github.com/libretro/gambatte-libretro.git    Gambatte
git clone https://github.com/libretro/smsplus-gx.git           SMSPlus
git clone https://github.com/libretro/Genesis-Plus-GX.git      GenesisPlus
git clone https://github.com/mgba-emu/mgba.git                 mGBA
git clone https://github.com/libretro/snes9x.git               Snes9x
git clone https://github.com/melonDS-emu/melonDS.git           melonDS
git clone https://github.com/libretro/mupen64plus-libretro.git mupen64plus-core
git clone https://github.com/libretro/pcsx_rearmed.git         pcsx_rearmed
git clone https://github.com/hrydgard/ppsspp.git               ppsspp
cd ppsspp && git submodule update --init --recursive && cd ..

# 2. 编译核心静态库（输出到 libs/）
bash RetroEmu/Core/build_mgba.sh
bash RetroEmu/Core/build_snes9x.sh
bash RetroEmu/Core/build_melonds.sh
bash RetroEmu/Core/build_mupen64plus.sh
bash RetroEmu/Core/build_pcsx.sh
bash RetroEmu/Core/build_ppsspp.sh interpreter    # interpreter 模式才是 App Store 合规的

# 3. 打开工程
open RetroEmu.xcodeproj     # 部署目标 iOS 15.6，Swift 5
```

NES / GB / GBA / SMS / MD 这几个核心由 Xcode 的 Run Script Phase 直接编译，
**核心源码缺失时工程无法通过编译**——这是最早会撞到的坑。

## 已知限制

- **PSP 只能跑解释器模式**。JIT 在 iOS 上不可用，解释器下速度约为实机的一半。
- 内置的核心桥接层是按各核心的 C API 手工写的，**升级核心版本大概率要改桥接层**，
  参数签名变化会直接编译失败。
- 商店截图脚本依赖已退役的模拟器机型（`Scripts/make_store_screenshots.sh`），
  新 Xcode 上不保证可用。
- `RetroEmu/Design/RTShotRunner.swift` 是截图专用的页面驱动，不属于正常使用路径。

## 关于 ROM

**本仓库不附带任何商业游戏 ROM，也不提供下载。** 唯一内置的是
`Tools/testrom/build_demo_rom.py` 用自有 6502 工具链生成的原创示例卡带
（接落下的卡带，计分，三次失误结束），随 MIT 发布。

## 许可证

应用层源码：[MIT](LICENSE)。
第三方模拟器核心：不在本仓库内，各自适用其上游许可证，见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

**注意：Snes9x 与 Genesis Plus GX 禁止商业使用**，GPL 组件要求整体以 GPL 发布。
因此本项目的构建产物**不能**用于商业分发。
