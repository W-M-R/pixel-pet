#!/usr/bin/env python3
"""
往模拟器里注入固定存档，让深层场景可复现。

## 为什么需要这个

像素断言要检查「吃饭时头有没有埋进碗」这类事，前提是场景里
**确实有碗、确实有两只宠物、确实喂得起**。靠 Maestro 从零玩到那一步
既慢又脆（要攒 800 买碗、攒 4000 买第二只）。

直接写存档最省事，而且模拟器的容器路径是可查的。

## 为什么不用 debug 面板

Debug 面板能发钱、能跳阶段，但它是**手动交互**，
每次都要点开设置 → 找到 debug 段 → 点几下。
写存档是一步到位的，而且状态完全确定（不依赖点击是否命中）。

用法：
    python3 tools/inject_save.py --scene bowl-two-pets
    python3 tools/inject_save.py --scene rich
"""
import argparse
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone

BUNDLE = "com.wmr.pixelpet"

# Swift 的 JSONEncoder 默认把 Date 编成「2001-01-01 以来的秒数」
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def apple_time(dt):
    """Python datetime -> Swift Date 的编码值"""
    return (dt - APPLE_EPOCH).total_seconds()


def container():
    """拿到 app 的数据容器路径。app 必须至少启动过一次。"""
    out = subprocess.run(
        ["xcrun", "simctl", "get_app_container", "booted", BUNDLE, "data"],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"拿不到容器路径，app 装了吗？\n{out.stderr.strip()}")
    d = os.path.join(out.stdout.strip(), "Library", "Application Support")
    os.makedirs(d, exist_ok=True)
    return d


def make_pet(breed, color=0, name="", days_old=30, satiety=1.0):
    """
    造一只宠物。

    时间戳是**倒推**的：这个 app 的状态全部由「距上次喂食多久」算出来
    （见 PetState 的设计），不存数值。所以要造「半饿的猫」就把
    lastFedAt 往前挪，而不是写一个 satiety 字段 —— 那个字段不存在。
    """
    now = datetime.now(timezone.utc)
    born = now - timedelta(days=days_old)
    # 成年饱食周期 8h。satiety=1 -> 刚喂过；satiety=0.5 -> 4h 前喂的
    fed_ago = (1.0 - satiety) * 8
    fed = now - timedelta(hours=fed_ago)
    return {
        "id": str(uuid.uuid4()).upper(),
        "breedID": breed,
        "species": breed,          # 降级字段，见 PetState.encode
        "colorIndex": color,
        "name": name,
        "bornAt": apple_time(born),
        "lastSeenAt": apple_time(now),
        "lastFedAt": apple_time(fed),
        "lastPlayedAt": apple_time(now),
        "lastCleanedAt": apple_time(now),
        "totalFeedCount": 20,
        "totalPlayCount": 15,
        "totalCleanCount": 8,
        "streakDays": 5,
        "lastStreakDay": apple_time(now),
        "wellCaredDays": 3,
        "triedBreeds": [breed],
        "triedColors": [color],
        "foodCounts": {},
    }


def make_wallet(coins, owned_breeds, furniture, selected=None, colors=None):
    now = datetime.now(timezone.utc)
    return {
        "coins": coins,
        "ledger": {
            "balance": coins,
            "totalIn": coins,
            "totalOut": 0,
            "recent": [],
            "totals": {},
        },
        "lastCollectedAt": apple_time(now),
        "totalEarned": coins,
        "todayEarnedByPet": {},
        "todayEarned": 0,
        "lastEarnDate": apple_time(now),
        "claimedRewards": [],
        "ownedBreeds": list(owned_breeds),
        "ownedFurniture": list(furniture),
        "triedColors": list(colors or [0]),
        "hasCompletedOnboarding": True,
        **({"selectedPetID": selected} if selected else {}),
    }


SCENES = {}


def scene(name):
    def deco(fn):
        SCENES[name] = fn
        return fn
    return deco


@scene("bowl-two-pets")
def _bowl_two(d):
    """有碗 + 两只宠物 + 都饿着。测「围到碗边吃」的主场景。"""
    cat = make_pet("cat", 0, "喵喵", satiety=0.2)
    dog = make_pet("dog", 1, "旺财", satiety=0.2)
    pets = [cat, dog]
    w = make_wallet(9000, ["cat", "dog"], ["bowl"],
                    selected=cat["id"], colors=[0, 1])
    return pets, w, {"slots": [
        # 碗放在偏左、靠前 —— 故意不用默认位置，
        # 这样「宠物站位跟着碗算」这件事才真的被验证到
        {"id": "bowl", "xRatio": 0.35, "depth": 0.30,
         "yOffset": 0, "scaleMul": 1, "z": 10.5}
    ]}


@scene("bowl-three-pets")
def _bowl_three(d):
    """三只抢一个碗。测多只并排是否都在碗口范围内。"""
    pets = [make_pet("cat", 0, "A", satiety=0.15),
            make_pet("dog", 1, "B", satiety=0.15),
            make_pet("cat", 2, "C", satiety=0.15)]
    w = make_wallet(9000, ["cat", "dog"], ["bowl"],
                    selected=pets[0]["id"], colors=[0, 1, 2])
    return pets, w, {"slots": [
        {"id": "bowl", "xRatio": 0.5, "depth": 0.35,
         "yOffset": 0, "scaleMul": 1, "z": 10.5}
    ]}


@scene("full-room")
def _full(d):
    """全部家具 + 两只宠物。测家具贴地、不遮挡按钮。"""
    pets = [make_pet("cat", 0, "喵喵"), make_pet("dog", 2, "旺财")]
    w = make_wallet(20000, ["cat", "dog"], ["bowl", "bed", "plant"],
                    selected=pets[0]["id"], colors=[0, 2])
    return pets, w, {"slots": [
        {"id": "bed", "xRatio": 0.20, "depth": 0.75,
         "yOffset": 0, "scaleMul": 1, "z": 7},
        {"id": "plant", "xRatio": 0.85, "depth": 0.65,
         "yOffset": 0, "scaleMul": 1, "z": 7},
        {"id": "bowl", "xRatio": 0.55, "depth": 0.25,
         "yOffset": 0, "scaleMul": 1, "z": 10.5},
    ]}


@scene("rich")
def _rich(d):
    """一只宠物 + 很多钱。测商店购买路径。"""
    pets = [make_pet("cat", 0, "土豪")]
    w = make_wallet(99999, ["cat"], [], selected=pets[0]["id"])
    return pets, w, {"slots": []}


@scene("legacy-room")
def _legacy(d):
    """
    旧格式 room.json（没有 depth 字段）。

    验证 `RoomLayout.Slot` 的手写解码真的能救旧存档 ——
    这曾经是个真 bug：合成 Codable 对有默认值的属性仍要求 key 存在，
    缺 depth 会整份解码失败，玩家摆好的布局无声重置。
    """
    pets = [make_pet("cat", 0, "老存档")]
    w = make_wallet(5000, ["cat"], ["bowl", "plant"], selected=pets[0]["id"])
    return pets, w, {"slots": [
        {"id": "bowl", "xRatio": 0.7, "yOffset": 12, "scaleMul": 1, "z": 8},
        {"id": "plant", "xRatio": 0.2, "yOffset": 5, "scaleMul": 1, "z": 7},
    ]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", required=True,
                    choices=sorted(SCENES), help="要注入的场景")
    a = ap.parse_args()

    d = container()
    pets, wallet, room = SCENES[a.scene](d)

    for name, data in (("pet.json", pets),
                       ("wallet.json", wallet),
                       ("room.json", room)):
        with open(os.path.join(d, name), "w") as f:
            json.dump(data, f, ensure_ascii=False)

    print(f"注入 {a.scene}：{len(pets)} 只宠物，"
          f"{wallet['coins']} 枚，家具 {wallet['ownedFurniture']}")


if __name__ == "__main__":
    main()
