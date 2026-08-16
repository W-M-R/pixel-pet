#!/bin/bash
# 分层依赖检查。
#
# 拆 SPM 模块能让编译器强制分层，但对 6200 行的单 app 来说成本过高
# （约 350 个 public + 资源方案妥协，见 docs/06-architecture.md）。
# 这个脚本用最粗糙的方式达到同样的约束力：**禁止反向引用**。
#
# 防的正是实际发生过的三种越界：
#   Models/Interaction  → Views/PixelIcon      （已修）
#   Models/Interaction  → Scenes/PetSpriteSheet（已修）
#   Scenes/RoomPalette  → Views/Pixel          （已修，Pixel 移到 Core/Design）
#
# 依赖方向：Core → Models → {Scenes, Services} → Views → App
#
# 用法：./tools/check_layers.sh
# 接进 Xcode build phase 可以让越界直接编译失败。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0

# 只看代码行 —— 注释里提到上层类型是合理的（解释为什么这么分层）。
# 做法：删掉行注释和文档注释后再匹配。
strip_comments() {
    sed -e 's://.*::' "$1"
}

# $1=层目录  $2=禁止引用的类型正则  $3=说明
check() {
    local dir="$1" pattern="$2" desc="$3"
    for f in "$dir"/*.swift; do
        [ -e "$f" ] || continue
        local hits
        hits=$(strip_comments "$f" | grep -nE "$pattern" || true)
        if [ -n "$hits" ]; then
            echo "❌ $f 违反分层：$desc"
            echo "$hits" | sed 's/^/     /'
            fail=1
        fi
    done
}

# Views 层的类型（Scenes / Services / Models 都不该引用）
VIEWS='\b(PixelIcon|PixelIconView|PixelPanel|PixelBar|PetHomeView|OnboardingView|ShopView|FoodPickerView|AchievementsView|PetSettingsView|DebugPanel|StatDimension)\b'
# Scenes 层的类型（Models / Services 不该引用）
SCENES='\b(PetScene|BubbleLayer|RoomRenderer|RoomPalette|PetSpriteSheet|RoomSpriteSheet)\b'

echo "检查分层依赖…"

# Core 是最底层，不该引用任何业务类型
check "Sources/Core/Design" '\b(PetState|PetStore|PetBreed|PetNeed|PetWallet)\b' \
      "Core 不得引用业务类型"
check "Sources/Core/Localization" '\b(PetState|PetStore|PetBreed|PetScene)\b' \
      "Core 不得引用业务类型"

# Models 不得引用 Views / Scenes
check "Sources/Models" "$VIEWS" "Models 不得引用 Views 的类型"
check "Sources/Models" "$SCENES" "Models 不得引用 Scenes 的类型"

# Scenes 不得引用 Views
check "Sources/Scenes" "$VIEWS" "Scenes 不得引用 Views 的类型"

# Services 不得引用 Views / Scenes
check "Sources/Services" "$VIEWS" "Services 不得引用 Views 的类型"
check "Sources/Services" "$SCENES" "Services 不得引用 Scenes 的类型"

if [ "$fail" -eq 0 ]; then
    echo "✅ 分层依赖正确：Core → Models → {Scenes, Services} → Views"
else
    echo
    echo "修法：把跨层的部分拆开 —— 纯数据留在下层，UI 配置放上层。"
    echo "参考 InteractionEffect（Models）与 Interaction（Views）的拆分。"
    exit 1
fi
