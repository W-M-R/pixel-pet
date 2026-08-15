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
        XCTAssertEqual(PetSpriteSheet.walkFrameSequence, [0, 1, 2, 1])
        XCTAssertEqual(PetSpriteSheet.walkFrameCount(row: 0), 3)
        XCTAssertFalse(PetSpriteSheet.walkFrameSequence.contains(PetSpriteSheet.idleColumn),
                       "走路序列不能包含第 4 格（坐姿）")
    }

    /// 帧序必须是往复而非硬循环 —— 首尾都是 passing pose 之外的姿态，
    /// 中间姿 col1 出现两次
    func testWalkSequenceIsPingPong() {
        let seq = PetSpriteSheet.walkFrameSequence
        XCTAssertEqual(seq.first, 0)
        XCTAssertEqual(seq.filter { $0 == 1 }.count, 2,
                       "passing pose 应出现两次")
    }

    /// idle 用第 4 格（坐姿）
    func testIdleUsesSittingFrame() {
        XCTAssertEqual(PetSpriteSheet.idleColumn, 3)
    }
}

// MARK: - 生命阶段与品种抽象
