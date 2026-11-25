#!/bin/bash
# export_public_repo.sh
# 把当前工作树导出一份可公开的干净快照到 .tmp/public-export/RetroEmu
#
# 做三件事：
#   1. 排除第三方核心、商店物料（AppStore/、legal/、docs/worktool/）、Xcode 本地状态
#   2. 抹掉个人信息（手机、邮箱、Team ID、真实 bundle id）
#   3. 建一个单提交的新仓库，避免把旧历史里的敏感串带出去
#
# 用法：
#   bash Scripts/export_public_repo.sh            # 导出并本地提交
#   bash Scripts/export_public_repo.sh --push     # 导出后 push 到已配置的 origin
#
# 完整历史留在本仓库，不随快照导出。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="$REPO_ROOT/.tmp/public-export"
OUT="$OUT_ROOT/RetroEmu"
PUSH="${1:-}"

# 公开仓库的提交身份：默认沿用本地配置，可用环境变量覆盖
# （推公开库时建议用 noreply 邮箱，避免真实邮箱被 commit 页暴露）
PUBLIC_NAME="${PUBLIC_AUTHOR_NAME:-$(git -C "$REPO_ROOT" config user.name)}"
PUBLIC_EMAIL="${PUBLIC_AUTHOR_EMAIL:-$(git -C "$REPO_ROOT" config user.email)}"

echo "==> 清理旧快照"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> 复制工作树（排除核心与本地物料）"
rsync -a \
  --exclude '.git' \
  --exclude '.tmp' \
  --exclude '.cache' \
  --exclude 'AppStore' \
  --exclude 'legal' \
  --exclude 'worktool' \
  --exclude 'DerivedData' \
  --exclude 'build' \
  --exclude 'libs' \
  --exclude 'ppsspp' \
  --exclude 'Gambatte' \
  --exclude 'GenesisPlus' \
  --exclude 'Nestopia' \
  --exclude 'SMSPlus' \
  --exclude 'Snes9x' \
  --exclude 'mGBA' \
  --exclude 'melonDS' \
  --exclude 'mupen64plus-core' \
  --exclude 'pcsx_rearmed' \
  --exclude '__pycache__' \
  --exclude 'xcuserdata' \
  --exclude '.DS_Store' \
  "$REPO_ROOT"/ "$OUT"/

echo "==> 抹掉个人信息"
PBX="$OUT/RetroEmu.xcodeproj/project.pbxproj"
if [ -f "$PBX" ]; then
  sed -i '' -E \
    -e 's/DEVELOPMENT_TEAM = [A-Z0-9]+;/DEVELOPMENT_TEAM = "";/g' \
    -e 's/com\.haohengcms\./com.example./g' \
    -e 's/com\.haoheng\./com.example./g' \
    "$PBX"
fi

# 兜底：任何残留的手机号 / 邮箱直接清掉
find "$OUT" -type f \( -name '*.md' -o -name '*.txt' -o -name '*.swift' -o -name '*.plist' -o -name '*.pbxproj' \) -print0 |
  xargs -0 -I{} sed -i '' -E \
    -e 's/\+?86?1[3-9][0-9]{9}//g' \
    -e 's/[A-Za-z0-9._%+-]+@163\.com//g' \
    -e 's/[A-Za-z0-9._%+-]+@qq\.com//g' \
    "{}"

echo "==> 校验：敏感串残留检查"
# 脚本自己会命中这些模式，排除掉
if grep -rInE --exclude='export_public_repo.sh' \
     "haohengcms|1[3-9][0-9]{9}@|DEVELOPMENT_TEAM = [A-Z0-9]{6,}" "$OUT" 2>/dev/null \
     | grep -v 'DEVELOPMENT_TEAM = ""'; then
  echo "❌ 仍有敏感串残留，检查上面列出的文件后再导出" >&2
  exit 1
fi
echo "✅ 未发现敏感串"

echo "==> 校验：第三方核心残留检查"
if [ -d "$OUT/libs" ] || [ -d "$OUT/ppsspp" ] || [ -d "$OUT/Snes9x" ] || [ -d "$OUT/mGBA" ]; then
  echo "❌ 核心目录被带进了快照" >&2
  exit 1
fi
echo "✅ 未发现核心目录"

echo "==> 初始化新仓库（单提交，不含旧历史）"
cd "$OUT"
git init -q
git add -A
git -c user.name="$PUBLIC_NAME" \
    -c user.email="$PUBLIC_EMAIL" \
    commit -q -m "Initial public snapshot: Pocket Museum / 掌机时光机

A handheld retro-game museum for iOS, retired from App Store submission
after Guideline 4.3(a) and released as an archive.

- Application layer: Swift + UIKit, hand-written design system, Metal renderer
- Ten emulator cores reached through Objective-C++ bridges (not vendored here)
- Original NES cartridge plus its offline 6502 toolchain in Tools/testrom"

echo
echo "✅ 快照已就绪：$OUT"
echo "   文件数：$(git ls-files | wc -l | tr -d ' ')"
echo
echo "下一步（手动）："
echo "  1. 在 GitHub 建空仓库，不要勾选 README/LICENSE"
echo "  2. cd $OUT && git remote add origin git@github.com:<user>/<repo>.git"
echo "  3. git push -u origin main"
echo "  4. 仓库 Settings 里补 Topics：ios emulator uikit metal swift"

if [ "$PUSH" = "--push" ]; then
  echo
  echo "==> 推送到 origin"
  git push -u origin HEAD
fi
