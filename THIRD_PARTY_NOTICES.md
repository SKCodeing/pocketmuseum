# 第三方组件声明

本仓库的 `RetroEmu/` 目录是应用层源码，采用 MIT 许可证（见 `LICENSE`）。

**本仓库不包含任何模拟器核心的源码或二进制。** 核心需要通过 `RetroEmu/Core/build_*.sh`
在本地自行获取并编译，各自适用其上游许可证。

## 为什么核心不入库

除了体积（数百 MB）之外，更重要的原因是**这些核心的许可证彼此冲突**：

- `GPL-2.0-only`（Gambatte、Nestopia、mupen64plus-core、pcsx_rearmed）与
  `GPL-3.0`（melonDS）互斥；
- Snes9x 与 Genesis Plus GX 的自定义许可证**禁止商业使用**，与任何 GPL 都不兼容。

因此不存在一个可以覆盖全部组件的单一许可证。把核心留在仓库外，是唯一能让
应用层的 MIT 许可证成立的形态。

## 核心清单

| 平台 | 核心 | 许可证 | 上游 |
|---|---|---|---|
| NES | Nestopia | GPL-2.0-only | https://github.com/libretro/nestopia |
| Game Boy / Color | Gambatte | GPL-2.0-only | https://github.com/libretro/gambatte-libretro |
| Game Boy Advance | mGBA | MPL-2.0 | https://github.com/mgba-emu/mgba |
| SNES | Snes9x | 自定义，**禁止商业使用** | https://github.com/snes9xgit/snes9x |
| Nintendo DS | melonDS | GPL-3.0 | https://github.com/melonDS-emu/melonDS |
| Nintendo 64 | mupen64plus-core | GPL-2.0-only | https://github.com/libretro/mupen64plus-libretro |
| PlayStation | PCSX-ReARMed | GPL-2.0-only | https://github.com/libretro/pcsx_rearmed |
| Genesis / Mega Drive / 32X / Sega CD | Genesis Plus GX | 自定义，**禁止商业使用** | https://github.com/libretro/Genesis-Plus-GX |
| Master System / Game Gear | SMS Plus | 自定义（见上游，无统一 LICENSE 文件） | https://github.com/libretro/smsplus-gx |
| PSP | PPSSPP | GPL-2.0-or-later | https://github.com/hrydgard/ppsspp |

## 对使用者的提醒

1. **不要把本项目的构建产物用于商业分发。** Snes9x 与 Genesis Plus GX 明确禁止
   商业使用；GPL 组件也要求整体以 GPL 发布，与 MIT 应用层无法共存。
2. 如果你要发布自己的分支，需自行逐个核对上表许可证，并替换掉非商业核心。
3. 本项目**不附带任何商业游戏 ROM**。仓库内的示例卡带
   （`Tools/testrom/build_demo_rom.py` 生成的 NES 程序）为本仓库原创，随 MIT 发布。

## 其他引用

- 封面图来自 libretro thumbnails（`thumbnails.libretro.com`），仅作元数据查询使用。
- RetroAchievements 为其运营方提供的第三方可选服务，与本项目无隶属关系。
- 所有主机名称、厂商名称均为其各自所有者的商标，本项目与上述厂商无关联。
