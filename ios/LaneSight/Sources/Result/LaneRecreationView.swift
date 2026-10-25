import SwiftUI

// MARK: - Lane recreation (Shot.dc.html — "Target vs actual" lane)
//
// A simulated top-down view of the lane from the foul line (bottom) to the pins (top), drawn from the
// shot's measured boards + the intended target. It shows:
//   • the TARGET line  — dashed blue (#33BFFF), the line the bowler aimed to play
//   • YOUR line        — solid green (#3DEB7C), the line reconstructed from the measured boards
//   • the oil pattern  — a faint purple (#C08BFF) house-shot taper, a visual REFERENCE only
//   • board markers, the arrow triangles, a pin rack, and labelled points
//     (Laydown / Arrows / Breakpoint +ft / Entry +angle).
//
// Every number is live from the shot record (metrics) and the session target. A board that wasn't
// measured/set is shown as "—" and its labelled point is omitted — nothing is fabricated. The purple
// oil shape is a generic house-shot reference (so labelled), not a measurement.
//
// Colors here are the lane-illustration hexes from the design spec; they are intentionally local to
// this drawing and are NOT part of the shared `LS` token set (Theme.swift is left untouched).
struct LaneRecreationView: View {
    // Intended target (boards) — from the session target set before the shot.
    let targetFeet: Double?
    let targetArrows: Double?
    let targetBreakpoint: Double?
    // Measured actuals (boards) — from the shot record metrics.
    let laydown: Double?
    let actualArrows: Double?
    let actualBreakpoint: Double?
    let breakpointDistanceFt: Double?
    let entryBoard: Double?
    let entryAngle: Double?
    let handed: String            // "R" | "L"
    let oilLengthFt: Double?       // reference only; nil → a generic house length

    // Lane illustration palette (design spec).
    private let cTargetLine = Color(hex: 0x33BFFF)
    private let cYourLine   = Color(hex: 0x3DEB7C)
    private let cOil        = Color(hex: 0xC08BFF)
    private let cWoodTop    = Color(hex: 0x7A5230)
    private let cWoodBottom = Color(hex: 0xB8844F)
    private let cBoard      = Color(hex: 0x5E3B1E)
    private let cPin        = Color(hex: 0xF5F6FA)

    var body: some View {
        GeometryReader { geo in
            let g = LaneGeometry(size: geo.size, handed: handed,
                                 bpDistFt: breakpointDistanceFt ?? 40,
                                 oilLengthFt: oilLengthFt ?? 38)
            ZStack {
                Canvas { ctx, _ in draw(ctx, g) }
                ForEach(labelChips(g)) { chip in
                    labelView(chip.text)
                        .position(chip.anchor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: 0x135079), lineWidth: 1))
        }
        .aspectRatio(342.0 / 330.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
    }

    // MARK: drawing

    private func draw(_ ctx: GraphicsContext, _ g: LaneGeometry) {
        // Background + wood trapezoid.
        ctx.fill(Path(g.rect), with: .color(Color(hex: 0x031A2D)))
        let lane = g.lanePath()
        ctx.fill(lane, with: .linearGradient(
            Gradient(colors: [cWoodTop, cWoodBottom]),
            startPoint: CGPoint(x: g.rect.midX, y: g.topY),
            endPoint: CGPoint(x: g.rect.midX, y: g.bottomY)))

        // Board seams (every board faint, every 5th a touch stronger).
        for b in 1...39 {
            var p = Path()
            p.move(to: g.point(dFt: 0, board: Double(b)))
            p.addLine(to: g.point(dFt: 60, board: Double(b)))
            ctx.stroke(p, with: .color(cBoard.opacity(b % 5 == 0 ? 0.35 : 0.12)), lineWidth: 0.6)
        }

        // Oil pattern — faint purple house-shot taper (reference only). Layered, narrowing toward the
        // end of the oil so the outsides read as dry.
        for (i, inset) in [2.0, 6.0, 10.0].enumerated() {
            let endFt = min(g.oilLengthFt, 58)
            var p = Path()
            p.move(to: g.point(dFt: 0, board: 2 + inset))
            p.addLine(to: g.point(dFt: endFt, board: 15 + inset))
            p.addLine(to: g.point(dFt: endFt, board: 25 - inset))
            p.addLine(to: g.point(dFt: 0, board: 38 - inset))
            p.closeSubpath()
            ctx.fill(p, with: .color(cOil.opacity(0.10 + Double(i) * 0.02)))
        }

        // Foul line (white).
        var foul = Path()
        foul.move(to: g.point(dFt: 0, board: 0.5))
        foul.addLine(to: g.point(dFt: 0, board: 39.5))
        ctx.stroke(foul, with: .color(cPin), lineWidth: 2)

        // Arrow triangles at the arrows (15 ft).
        for b in stride(from: 5.0, through: 35.0, by: 5.0) {
            let tip = g.point(dFt: 17, board: b)
            let baseL = g.point(dFt: 14, board: b + 0.9)
            let baseR = g.point(dFt: 14, board: b - 0.9)
            var tri = Path()
            tri.move(to: tip); tri.addLine(to: baseL); tri.addLine(to: baseR); tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(hex: 0x3A2412)))
        }

        // Pin rack (standard 10-pin triangle) just inside the pin deck.
        for pin in pinBoards {
            let c = g.point(dFt: pin.ft, board: pin.board)
            let r: CGFloat = 3.2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(cPin))
        }

        // Target line (dashed blue) through the intended points that exist.
        if let path = smoothPath(targetPoints(g)) {
            ctx.stroke(path, with: .color(cTargetLine),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [6, 5]))
        }
        // Your line (solid green) through the measured points that exist.
        if let path = smoothPath(yourPoints(g)) {
            // subtle dark underlay for contrast on the wood
            ctx.stroke(path, with: .color(Color(hex: 0x001018).opacity(0.4)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.stroke(path, with: .color(cYourLine),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        }

        // Point dots.
        for chip in labelChips(g) {
            let r: CGFloat = 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: chip.point.x - r, y: chip.point.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(hex: 0x000F17)))
            ctx.stroke(Path(ellipseIn: CGRect(x: chip.point.x - r, y: chip.point.y - r, width: r * 2, height: r * 2)),
                       with: .color(cPin), lineWidth: 2)
        }
    }

    // MARK: lines

    /// Your measured line: laydown → arrows → breakpoint → entry (only the points that exist).
    private func yourPoints(_ g: LaneGeometry) -> [CGPoint] {
        var pts: [CGPoint] = []
        if let b = laydown { pts.append(g.point(dFt: 2, board: b)) }
        if let b = actualArrows { pts.append(g.point(dFt: 15, board: b)) }
        if let b = actualBreakpoint { pts.append(g.point(dFt: g.bpDistFt, board: b)) }
        if let b = entryBoard { pts.append(g.point(dFt: 60, board: b)) }
        return pts
    }

    /// Intended target line: feet (stance) → arrows → breakpoint (only the points that exist).
    private func targetPoints(_ g: LaneGeometry) -> [CGPoint] {
        var pts: [CGPoint] = []
        if let b = targetFeet { pts.append(g.point(dFt: 0, board: b)) }
        if let b = targetArrows { pts.append(g.point(dFt: 15, board: b)) }
        if let b = targetBreakpoint { pts.append(g.point(dFt: g.bpDistFt, board: b)) }
        return pts
    }

    // MARK: labels

    private struct Chip: Identifiable {
        let id: String
        let text: String
        let point: CGPoint      // the dot
        let anchor: CGPoint     // where the text chip sits
    }

    private func labelChips(_ g: LaneGeometry) -> [Chip] {
        var chips: [Chip] = []
        func add(_ id: String, _ text: String, dFt: Double, board: Double?) {
            guard let board else { return }
            let p = g.point(dFt: dFt, board: board)
            // Offset the chip toward the open side of the lane so it doesn't sit on the line.
            let toLeft = p.x > g.rect.midX
            let dx: CGFloat = toLeft ? -46 : 46
            var ax = p.x + dx
            ax = min(max(ax, 44), g.rect.width - 44)
            let ay = min(max(p.y, 14), g.rect.height - 14)
            chips.append(Chip(id: id, text: text, point: p, anchor: CGPoint(x: ax, y: ay)))
        }
        add("laydown", "Laydown \(bd(laydown))", dFt: 2, board: laydown)
        add("arrows", "Arrows \(bd(actualArrows))", dFt: 15, board: actualArrows)
        let bpFt = breakpointDistanceFt.map { " · \(Int($0.rounded())) ft" } ?? ""
        add("bp", "BP \(bd(actualBreakpoint))\(bpFt)", dFt: g.bpDistFt, board: actualBreakpoint)
        let ang = entryAngle.map { " · \(String(format: "%.1f", $0))°" } ?? ""
        add("entry", "Entry \(bd(entryBoard))\(ang)", dFt: 60, board: entryBoard)
        return chips
    }

    private func labelView(_ text: String) -> some View {
        Text(text)
            .font(.lsRoboto(10, weight: .medium))
            .foregroundStyle(cPin)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(hex: 0x000C18).opacity(0.88), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize()
    }

    private var pinBoards: [(ft: Double, board: Double)] {
        // 10-pin triangle centred on board 20, ~60 ft. Rows get wider toward the back.
        [(57, 20),
         (58, 17), (58, 23),
         (59, 14), (59, 20), (59, 26),
         (60, 11), (60, 17), (60, 23), (60, 29)]
    }

    private func bd(_ v: Double?) -> String { v.map { Fmt.number($0) } ?? "—" }

    // MARK: smooth path (Catmull-Rom through the points)

    private func smoothPath(_ pts: [CGPoint]) -> Path? {
        guard pts.count >= 2 else { return nil }
        var path = Path()
        path.move(to: pts[0])
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    // MARK: accessibility

    /// One combined description of the lines + points (mirrors the design's aria-label). Honest about
    /// missing values.
    private var voiceOverLabel: String {
        func f(_ v: Double?, _ dp: Int = 0) -> String {
            guard let v else { return "not set" }
            return dp == 0 ? Fmt.number(v) : String(format: "%.\(dp)f", v)
        }
        var s = "Simulated lane from the foul line to the pins. "
        s += "Target line, dashed blue: feet \(f(targetFeet)), arrows \(f(targetArrows)), breakpoint \(f(targetBreakpoint)). "
        s += "Your line, green: laydown \(f(laydown)), arrows \(f(actualArrows)), "
        if let d = breakpointDistanceFt {
            s += "breakpoint \(f(actualBreakpoint)) at \(Int(d.rounded())) feet, "
        } else {
            s += "breakpoint \(f(actualBreakpoint)), "
        }
        if let a = entryAngle {
            s += "entry \(f(entryBoard, 1)) at \(f(a, 1)) degrees. "
        } else {
            s += "entry \(f(entryBoard, 1)). "
        }
        s += "The faint purple shading is the house-shot oil pattern, shown for reference."
        return s
    }
}

// MARK: - Lane coordinate system
//
// Maps (distance in feet from the foul line, board 1…39) to a point in the drawing rect, with a mild
// top-down perspective: the lane narrows toward the pins and equal foot-steps compress with distance.
private struct LaneGeometry {
    let rect: CGRect
    let topY: CGFloat
    let bottomY: CGFloat
    let handed: String
    let bpDistFt: Double
    let oilLengthFt: Double

    private let laneLengthFt = 60.0
    private let perspective = 3.2        // far/near depth ratio (bigger = more compression)

    init(size: CGSize, handed: String, bpDistFt: Double, oilLengthFt: Double) {
        self.rect = CGRect(origin: .zero, size: size)
        self.topY = size.height * 0.06
        self.bottomY = size.height * 0.95
        self.handed = handed
        self.bpDistFt = max(10, min(bpDistFt, 58))
        self.oilLengthFt = max(10, oilLengthFt)
    }

    /// Screen fraction (0 at foul line, 1 at pin deck) for a distance, with perspective compression.
    private func depthFrac(_ dFt: Double) -> CGFloat {
        let t = max(0, min(dFt / laneLengthFt, 1))
        let depth = 1 + t * (perspective - 1)
        let s = (1 - 1 / depth) / (1 - 1 / perspective)
        return CGFloat(s)
    }

    private func y(_ dFt: Double) -> CGFloat { bottomY + (topY - bottomY) * depthFrac(dFt) }

    /// Lane left/right x at a given depth fraction (foul line full width → narrow pin deck).
    private func edges(_ s: CGFloat) -> (CGFloat, CGFloat) {
        let w = rect.width
        let left = (0.06 + (0.36 - 0.06) * s) * w
        let right = (0.94 + (0.64 - 0.94) * s) * w
        return (left, right)
    }

    /// Fraction across the lane (0 = left edge on screen, 1 = right edge). Board 1 is the right gutter for
    /// a right-hander, the left gutter for a left-hander — so the hook reads correctly either way.
    private func boardFrac(_ board: Double) -> CGFloat {
        let b = max(0.5, min(board, 39.5))
        return handed.uppercased() == "L" ? CGFloat((b - 0.5) / 39) : CGFloat((39.5 - b) / 39)
    }

    func point(dFt: Double, board: Double) -> CGPoint {
        let s = depthFrac(dFt)
        let (l, r) = edges(s)
        return CGPoint(x: l + boardFrac(board) * (r - l), y: y(dFt))
    }

    func lanePath() -> Path {
        var p = Path()
        p.move(to: point(dFt: 0, board: 0.5))
        p.addLine(to: point(dFt: 0, board: 39.5))
        p.addLine(to: point(dFt: 60, board: 39.5))
        p.addLine(to: point(dFt: 60, board: 0.5))
        p.closeSubpath()
        return p
    }
}
