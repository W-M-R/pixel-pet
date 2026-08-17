import XCTest
@testable import PixelPet

/// 几何与渲染：2.5D 地板、精灵表帧布局。
///
/// 这些是纯值类型的数学，零 SpriteKit 依赖 —— 所以能测。
/// `FloorPlaneTests` 锁住了两个真实回归（缩放连续性、无大跳变）。

final class FloorPlaneTests: XCTestCase {

    private func makeFloor() -> FloorPlane {
        FloorPlane(backY: 280, frontY: 50, width: 400)
    }

    func testDepthMapping() {
        let f = makeFloor()
        XCTAssertEqual(f.depth(atY: 50), 0, accuracy: 0.001, "前缘 = depth 0")
        XCTAssertEqual(f.depth(atY: 280), 1, accuracy: 0.001, "墙脚 = depth 1")
        XCTAssertEqual(f.depth(atY: 165), 0.5, accuracy: 0.01, "中点 = depth 0.5")
        // 越界要钳住
        XCTAssertEqual(f.depth(atY: -100), 0)
        XCTAssertEqual(f.depth(atY: 9999), 1)
    }

    func testDepthYRoundTrip() {
        let f = makeFloor()
        for d in stride(from: 0.0, through: 1.0, by: 0.1) {
            let y = f.y(atDepth: CGFloat(d))
            XCTAssertEqual(f.depth(atY: y), CGFloat(d), accuracy: 0.001)
        }
    }

    /// 远处可行走范围必须比近处窄 —— 这是透视成立的前提
    func testPerspectiveNarrowsWithDepth() {
        let f = makeFloor()
        let near = f.xRange(atDepth: 0)
        let far = f.xRange(atDepth: 1)
        let nearWidth = near.upperBound - near.lowerBound
        let farWidth = far.upperBound - far.lowerBound
        XCTAssertGreaterThan(nearWidth, farWidth, "远处应该更窄")
        XCTAssertEqual(nearWidth, 400, accuracy: 0.001, "最近处占满屏宽")
    }

    /// 远处宠物必须更小
    func testScaleShrinksWithDepth() {
        let f = makeFloor()
        XCTAssertEqual(f.scaleFactor(atDepth: 0), 1, accuracy: 0.001)
        XCTAssertLessThan(f.scaleFactor(atDepth: 1), f.scaleFactor(atDepth: 0))
        XCTAssertEqual(f.scaleFactor(atDepth: 1), f.minScaleRatio, accuracy: 0.001)
    }

    /// clamp 必须把任意点拉回地板内，且尊重该深度的横向范围
    func testClampKeepsPointOnFloor() {
        let f = makeFloor()
        // 远处角落：x 应该被推进梯形内
        let c = f.clamp(CGPoint(x: 0, y: 280))
        XCTAssertGreaterThan(c.x, 0, "远处最左应被内缩")
        XCTAssertEqual(c.y, 280, accuracy: 0.001)

        // 超出上下界
        XCTAssertEqual(f.clamp(CGPoint(x: 200, y: 9999)).y, 280, accuracy: 0.001)
        XCTAssertEqual(f.clamp(CGPoint(x: 200, y: -50)).y, 50, accuracy: 0.001)
    }

    // MARK: - 深度缩放（修「走动时一闪一闪」）

    /// 缩放必须**连续**，不能有离散跳档。
    ///
    /// 曾经把缩放量化到 1/3 网格（Unity Pixel Perfect Camera 的思路），
    /// 但那套方案要求全场景共用一个像素网格 —— 伪深度让每只宠物在不同 y
    /// 有不同缩放，前提不成立。实测 young 全程只剩 3.0/2.667/2.333 三档，
    /// 相邻档差 11%，走动时「猛地缩一下」，比原本的抖动更刺眼。
    ///
    /// 现在靠 `PetSpriteSheet.prescale`（nearest 整数预放大 + linear 连续
    /// 缩小）解决采样问题，缩放本身保持连续。这个测试防量化回归。
    func testPetScaleIsContinuous() {
        let f = makeFloor()
        var distinct = Set<CGFloat>()
        for i in 0...100 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 100)
            distinct.insert((s * 10000).rounded() / 10000)
        }
        XCTAssertGreaterThan(distinct.count, 50,
                             "缩放应连续变化，出现离散档位说明又被量化了")
    }

    /// 相邻深度的缩放差必须很小 —— 大跳变就是肉眼可见的「闪」
    func testPetScaleHasNoLargeJumps() {
        let f = makeFloor()
        var prev = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 0)
        for i in 1...200 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 200)
            let jump = abs(s - prev) / prev
            XCTAssertLessThan(jump, 0.01,
                              "depth \(Double(i)/200) 处缩放跳变 \(jump * 100)%，应 <1%")
            prev = s
        }
    }

    /// 远处仍须更小
    func testPetScaleShrinksWithDepth() {
        let f = makeFloor()
        let near = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 0)
        let far = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 1)
        XCTAssertLessThan(far, near)
        XCTAssertEqual(far / near, f.minScaleRatio, accuracy: 0.001)
    }

    /// 单调性
    func testPetScaleIsMonotonic() {
        let f = makeFloor()
        var prev = CGFloat.greatestFiniteMagnitude
        for i in 0...100 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 100)
            XCTAssertLessThanOrEqual(s, prev + 0.0001)
            prev = s
        }
    }

    /// 预放大倍数必须是整数且 >1 —— 非整数放大会先糊一次像素画
    func testPrescaleIsIntegerAndGreaterThanOne() {
        XCTAssertGreaterThan(PetSpriteSheet.prescale, 1)
        XCTAssertEqual(PetSpriteSheet.prescale,
                       Int(PetSpriteSheet.prescale),
                       "必须是整数倍放大")
    }

    func testRandomPointsAlwaysOnFloor() {
        let f = makeFloor()
        for _ in 0..<500 {
            let p = f.randomPoint()
            XCTAssertGreaterThanOrEqual(p.y, f.frontY)
            XCTAssertLessThanOrEqual(p.y, f.backY)
            let range = f.xRange(atDepth: f.depth(atY: p.y))
            XCTAssertGreaterThanOrEqual(p.x, range.lowerBound)
            XCTAssertLessThanOrEqual(p.x, range.upperBound)
        }
    }
}

// MARK: - Sprite sheet 帧数

final class PetSpriteSheetTests: XCTestCase {

    /// **走路是 3 帧 ping-pong，不是 4 帧循环。**
    ///
    /// LPC Cats and Dogs 每方向只有 3 帧走路，第 4 格是坐/趴姿
    /// （cat r0c3 = 252px 的趴卧，cat r1c3/r2c3 = 完全空白）。
    /// 按 4 帧播会导致走路每周期「抽」一下趴下或闪一帧空白 ——
    /// 这就是「走路一顿一顿」的根因。防回归。
    func testWalkUsesThreeFramePingPong() {
        let l = PetSheetLayout.lpc(footPadding: 5)
        XCTAssertEqual(l.walkSequence, [0, 1, 2, 1])
        XCTAssertEqual(l.walkFrameCount, 3)
        XCTAssertFalse(l.walkSequence.contains(l.idleColumn ?? -1),
                       "走路序列不能包含第 4 格（坐姿）")
    }

    /// 帧序必须是往复而非硬循环 —— 首尾都是 passing pose 之外的姿态，
    /// 中间姿 col1 出现两次
    func testWalkSequenceIsPingPong() {
        let seq = PetSheetLayout.lpc(footPadding: 5).walkSequence
        XCTAssertEqual(seq.first, 0)
        XCTAssertEqual(seq.filter { $0 == 1 }.count, 2,
                       "passing pose 应出现两次")
    }

    /// idle 用第 4 格（坐姿）
    func testIdleUsesSittingFrame() {
        XCTAssertEqual(PetSheetLayout.lpc(footPadding: 5).idleColumn, 3)
    }

    /// **布局必须是每个品种自己的，不能有第二份真相。**
    ///
    /// 修的 bug：`PetBreed.colorCount` 与 `PetSpriteSheet.colorCount`
    /// 曾经并存。加一个 2 色品种时，毛色选择器读前者显示 2 格，
    /// 而取帧读后者按 4 色算列偏移 → 取到越界列。
    /// `SKTexture(rect:in:)` 不会崩，只是取到空白或邻帧，静默出错。
    func testBreedColorCountComesFromLayout() {
        for b in PetBreed.all {
            XCTAssertEqual(b.colorCount, b.layout.colorCount,
                           "\(b.id) 的毛色数有两份真相")
            XCTAssertEqual(b.footPadding, b.layout.footPadding)
        }
    }

    /// 布局自身要自洽 —— 走路帧不能超出一个循环的列数
    func testLayoutIsSelfConsistent() {
        for b in PetBreed.all {
            let l = b.layout
            XCTAssertGreaterThan(l.colorCount, 0)
            XCTAssertGreaterThan(l.columnsPerColor, 0)
            XCTAssertFalse(l.walkSequence.isEmpty)
            for col in l.walkSequence {
                XCTAssertLessThan(col, l.columnsPerColor,
                                  "\(b.id) 走路帧 \(col) 超出循环列数")
            }
            if let idle = l.idleColumn {
                XCTAssertLessThan(idle, l.columnsPerColor)
            }
            XCTAssertEqual(l.facingRows.count, PetSpriteSheet.Facing.allCases.count)
            XCTAssertGreaterThan(l.footPadding, 0)
            XCTAssertLessThan(l.footPadding, l.cell)
        }
    }
}

// MARK: - 生命阶段与品种抽象

/// 布局抽象是否真的支持「长得不像猫狗」的动物。
///
/// 这组测试是**抽象的验收标准**。之前布局是 `PetSpriteSheet` 的全局常量，
/// 注释却写着「加新宠物不需要改渲染代码」—— 那只在新素材严格照抄
/// LPC 布局时成立。现在验证：换布局确实不用改渲染代码。
final class SheetLayoutFlexibilityTests: XCTestCase {

    /// 48×48 格、2 毛色、每方向 4 帧走路、没有坐姿列的假想动物
    private var exotic: PetSheetLayout {
        PetSheetLayout(cell: 48,
                       columnsPerColor: 4,
                       colorCount: 2,
                       walkSequence: [0, 1, 2, 3],
                       idleColumn: nil,          // 没有专门的坐姿帧
                       facingRows: [0, 2, 3, 1], // 行序也不同
                       eatRow: nil,              // 没有进食帧
                       footPadding: 6,
                       sleepColumns: 2,
                       sleepRows: 2)
    }

    func testExoticLayoutIsSelfConsistent() {
        let l = exotic
        XCTAssertEqual(l.frameSize, CGSize(width: 48, height: 48))
        XCTAssertEqual(l.walkFrameCount, 4, "4 帧走路应被如实报告")
        XCTAssertNil(l.idleColumn)
        for col in l.walkSequence {
            XCTAssertLessThan(col, l.columnsPerColor)
        }
    }

    /// 行语义不同也要能正确映射朝向
    func testFacingRowsAreRemapped() {
        let l = exotic
        XCTAssertEqual(PetSpriteSheet.Facing.right.row(in: l), 0)
        XCTAssertEqual(PetSpriteSheet.Facing.front.row(in: l), 2)
        XCTAssertEqual(PetSpriteSheet.Facing.back.row(in: l), 3)
        XCTAssertEqual(PetSpriteSheet.Facing.left.row(in: l), 1)
    }

    /// 没有进食行时要降级，而不是取到不存在的第 4 行
    func testEatRowFallsBackWhenAbsent() {
        let row = PetSpriteSheet.Action.eat.row(in: exotic)
        XCTAssertEqual(row, 0, "无进食帧应回退到侧视行")

        // LPC 的仍是 r4
        XCTAssertEqual(PetSpriteSheet.Action.eat.row(in: PetBreed.cat.layout), 4)
    }

    /// LPC 布局作为基准不能被改动 —— 猫狗依赖它
    func testLPCLayoutUnchanged() {
        let l = PetSheetLayout.lpc(footPadding: 5)
        XCTAssertEqual(l.cell, 32)
        XCTAssertEqual(l.colorCount, 4)
        XCTAssertEqual(l.columnsPerColor, 4)
        XCTAssertEqual(l.walkSequence, [0, 1, 2, 1])
        XCTAssertEqual(l.idleColumn, 3)
        XCTAssertEqual(l.facingRows, [0, 1, 2, 3])
        XCTAssertEqual(l.eatRow, 4)
        XCTAssertEqual(l.sleepColumns, 4)
        XCTAssertEqual(l.sleepRows, 2)
    }
}

/// 多宠渲染。
///
/// 这组测试锁住一个**极难从表象反推**的 bug：
/// `SKSpriteNode()` 之后再赋 `.texture` 不会同步 `size`，节点停在 0×0。
/// 屏幕上一只宠物都看不见，而 position / scale / parent / alpha / texture
/// 全都是对的 —— 我靠往场景里打 `size=%.0fx%.0f` 才定位到。
@MainActor
final class PetActorTests: XCTestCase {

    private func makeActor(_ breed: PetBreed = .cat, color: Int = 0) -> PetActor {
        PetActor(petID: "t", breed: breed, colorIndex: color,
                 stage: .adult, pixelScale: 4)
    }

    /// **节点必须有非零尺寸**，否则有纹理也画不出来
    func testNodeHasNonZeroSize() {
        let a = makeActor()
        XCTAssertNotNil(a.node.texture, "取不到纹理说明素材没打进 bundle")
        XCTAssertGreaterThan(a.node.size.width, 0,
                             "size 是 0 —— 大概率是先 SKSpriteNode() 再赋 texture")
        XCTAssertGreaterThan(a.node.size.height, 0)
    }

    /// 每只 actor 各持一份行为状态 —— 共用的话一只走路另一只会跟着走
    func testActorsHaveIndependentBehavior() {
        let a = makeActor(.cat)
        let b = makeActor(.dog)
        a.behavior = .wandering(target: CGPoint(x: 10, y: 10))
        b.behavior = .sleeping

        if case .wandering = a.behavior {} else { XCTFail("a 的行为被覆盖了") }
        if case .sleeping = b.behavior {} else { XCTFail("b 的行为被覆盖了") }

        a.facing = .left
        b.facing = .right
        XCTAssertEqual(a.facing, .left)
        XCTAssertEqual(b.facing, .right)
    }

    /// 外观没变时不该报告「变了」—— 否则每帧都重贴图
    func testUpdateAppearanceOnlyReportsRealChanges() {
        let a = makeActor(.cat, color: 1)
        XCTAssertFalse(a.updateAppearance(breed: .cat, colorIndex: 1, stage: .adult),
                       "没变却报告变了")
        XCTAssertTrue(a.updateAppearance(breed: .cat, colorIndex: 2, stage: .adult),
                      "换毛色该报告变了")
        XCTAssertTrue(a.updateAppearance(breed: .dog, colorIndex: 2, stage: .adult),
                      "换品种该报告变了")
        XCTAssertTrue(a.updateAppearance(breed: .dog, colorIndex: 2, stage: .young),
                      "换阶段该报告变了")
    }

    /// footPadding 是 per-breed 的，脚底位置要跟着不同
    func testFeetYUsesBreedFootPadding() {
        let cat = makeActor(.cat)
        let dog = makeActor(.dog)
        cat.node.position = CGPoint(x: 0, y: 100)
        dog.node.position = CGPoint(x: 0, y: 100)
        XCTAssertNotEqual(cat.feetY, dog.feetY,
                          "cat footPadding=5 / dog=3，脚底不该一样")
    }

    /// 深度越大（越远）缩放越小
    func testScaleShrinksWithDepth() {
        let a = makeActor()
        XCTAssertGreaterThan(a.scale(atDepth: 0), a.scale(atDepth: 1))
    }
}
