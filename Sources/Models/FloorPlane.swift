import CoreGraphics

/// 地板平面。把「一条水平线」升级成「一块可行走的地面」。
///
/// 这是 2.5D（伪 3D）的常见做法：屏幕 y 坐标同时编码**远近**。
/// 越靠上 = 越靠里（远），越靠下 = 越靠外（近）。
///
/// ```
///   ┌────────────────────┐
///   │      墙 + 窗        │
///   ├────────────────────┤  wallBase：墙脚线 = 地板最远处 (depth 1.0)
///   │ ╲   远              │
///   │  ╲                 │  地板梯形：远处窄，近处宽
///   │   ╲      🐕        │
///   │    ╲  近           │
///   └────────────────────┘  frontEdge：地板最近处 (depth 0.0)
/// ```
///
/// 两件事随 depth 变化：
/// 1. **横向可行走范围**：远处窄、近处宽（透视收缩）
/// 2. **宠物缩放**：远处小、近处大
struct FloorPlane {

    /// 地板最远处的 y（墙脚线）
    let backY: CGFloat
    /// 地板最近处的 y（屏幕下缘往上留一点）
    let frontY: CGFloat
    /// 屏幕宽
    let width: CGFloat

    /// 远处边缘相对屏宽的内缩比例。0.18 表示最远处两侧各缩进 18%，
    /// 形成梯形透视。太大会让房间显得像漏斗，太小则没有纵深感。
    var perspectiveInset: CGFloat = 0.16

    /// 最远处宠物的缩放系数（相对最近处）。
    /// 0.72 是个折中：能看出远近差别，又不至于让宠物在里侧小得看不清。
    var minScaleRatio: CGFloat = 0.72

    init(backY: CGFloat, frontY: CGFloat, width: CGFloat) {
        self.backY = backY
        self.frontY = frontY
        self.width = width
    }

    /// 地板纵深范围（点）
    var depthSpan: CGFloat { max(1, backY - frontY) }

    /// 把 y 转成 depth（0 = 最近，1 = 最远）
    func depth(atY y: CGFloat) -> CGFloat {
        let d = (y - frontY) / depthSpan
        return min(1, max(0, d))
    }

    /// 把 depth 转成 y
    func y(atDepth depth: CGFloat) -> CGFloat {
        frontY + min(1, max(0, depth)) * depthSpan
    }

    /// 某个 depth 处的可行走横向范围
    func xRange(atDepth depth: CGFloat) -> ClosedRange<CGFloat> {
        let inset = width * perspectiveInset * depth
        let lo = inset
        let hi = width - inset
        return lo...max(lo + 1, hi)
    }

    /// 某个 depth 处的缩放倍数（相对基准 pixelScale）
    func scaleFactor(atDepth depth: CGFloat) -> CGFloat {
        1 - (1 - minScaleRatio) * depth
    }

    /// 把任意点吸附到地板内的合法位置
    func clamp(_ point: CGPoint) -> CGPoint {
        let y = min(backY, max(frontY, point.y))
        let range = xRange(atDepth: depth(atY: y))
        return CGPoint(x: min(range.upperBound, max(range.lowerBound, point.x)), y: y)
    }

    /// 地板内的随机点。
    ///
    /// depth 用平方分布偏向近处 —— 均匀分布会让宠物大量时间待在远处
    /// 那条窄带里，看着像贴着墙走。
    func randomPoint() -> CGPoint {
        let d = pow(CGFloat.random(in: 0...1), 1.6)
        let range = xRange(atDepth: d)
        // 两侧再留一点边距，别贴着墙角
        let margin = (range.upperBound - range.lowerBound) * 0.06
        return CGPoint(x: .random(in: (range.lowerBound + margin)...(range.upperBound - margin)),
                       y: y(atDepth: d))
    }
}
