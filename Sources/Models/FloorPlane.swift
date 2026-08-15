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

    /// 远处边缘相对屏宽的内缩比例。
    ///
    /// 曾经用 0.16 并画了阶梯状侧墙来显示这个梯形，结果房间看着像漏斗 ——
    /// 真实房间的地板轮廓不会收缩得那么厉害。现在只留很小的内缩（0.04），
    /// 作用是**避免宠物贴到屏幕最边缘**，而不是制造视觉透视。
    ///
    /// 纵深感改由地板纹理（横向木纹间距递增）承担，那个更接近真实观感。
    var perspectiveInset: CGFloat = 0.04

    /// 最远处宠物的缩放系数（相对最近处）。
    ///
    /// 0.78：轮廓不再收缩后，纵深主要靠这个和地板纹理来体现，
    /// 但也不能太小 —— 像素画缩放到非整数倍会破坏像素网格，
    /// 缩得越狠越明显。
    var minScaleRatio: CGFloat = 0.78

    /// 缩放量化步长（相对 pixelScale 的倍数）。
    ///
    /// **这是修「走动时忽大忽小」的关键。**
    ///
    /// nearest 采样下，源图 1 像素渲染成 `scale` 个 pt。scale 是非整数时
    /// （比如 3.736），32 个源像素铺到 119.6pt —— 有些像素占 4pt、
    /// 有些占 3pt，而且**哪些占 4pt 会随 scale 连续漂移**。
    /// 走动时 y 每帧都在变 → scale 每帧都在变 → 像素块边界不停重新分配，
    /// 看起来就是整只宠物在忽大忽小、边缘发抖。
    ///
    /// 解法是把 scale 量化成离散档位：走动时大部分时间 scale 完全不变，
    /// 只在跨档时切换一次。代价是切换瞬间有一次轻微跳变，
    /// 远好过持续抖动。
    ///
    /// 取 1/3 是因为主流 iPhone 是 3x 屏（1pt = 3 物理像素），
    /// scale 为 1/3 的倍数时每个源像素恰好占整数个物理像素。
    var scaleQuantum: CGFloat = 1.0 / 3.0

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

    /// 某个 depth 处的缩放倍数（相对基准 pixelScale）。**连续值。**
    ///
    /// 影子等非像素元素可以直接用这个；宠物必须走
    /// `quantizedScale(pixelScale:depth:)`，否则像素网格会抖。
    func scaleFactor(atDepth depth: CGFloat) -> CGFloat {
        1 - (1 - minScaleRatio) * depth
    }

    /// 宠物的最终缩放，已量化到 `scaleQuantum` 的整数倍。
    ///
    /// - Parameters:
    ///   - pixelScale: 基准像素密度
    ///   - bodyScale: 生命阶段体型系数
    ///   - depth: 当前深度
    func quantizedScale(pixelScale: CGFloat,
                        bodyScale: CGFloat,
                        depth: CGFloat) -> CGFloat {
        let raw = pixelScale * bodyScale * scaleFactor(atDepth: depth)
        guard scaleQuantum > 0 else { return raw }
        let steps = (raw / scaleQuantum).rounded()
        // 至少保留一档，避免极端参数下缩放归零
        return max(scaleQuantum, steps * scaleQuantum)
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
