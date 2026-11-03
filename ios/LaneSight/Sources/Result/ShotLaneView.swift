import SwiftUI
import SceneKit

/// DEC-088/090 Shot card lane view (Figma 564:360). A LIVE 3D render of the shot from its measured data —
/// never a static image or the old flat recreation. True-scale lane (39 boards / 41.5 in, 60 ft to the head
/// pin), arrows, approach dots and pins all in frame; the ball path is the server's smoothed curve (path_fit),
/// the target line is drawn from the intended laydown to the pocket. Four glass labels are pinned to points on
/// the path (projected from 3D), with the result chip and a legend overlaid.
///
/// Camera: ~30 ft behind the foul line, 10 ft up, looking 15.5 ft down the lane, 16° vertical FOV.
/// Coordinate frame (feet): z = down the lane (foul line 0 → pins −60, into the screen); x = lateral
/// (board 1 on the bowler's right = +x for a right-hander); y = up.
struct ShotLaneView: View {
    let result: ShotResult
    @State private var labels: [ProjectedLabel] = []

    private static let laneLenFt = 60.0
    static let boardWidthFt = (41.5 / 39.0) / 12.0        // 0.0887 ft per board

    /// Lateral position of a board in feet. Board 20 is the center; board 1 (right gutter) is +x for a RH.
    static func xFt(_ board: Double, rightHanded: Bool) -> Double {
        let dx = (20.0 - board) * boardWidthFt
        return rightHanded ? dx : -dx
    }

    private var farLaneNotRead: Bool { result.coachLane?.status == "not_read" }
    private var rightHanded: Bool { true }   // record is already in the handed frame; board polarity handled server-side

    // Right-side callout column (2026-10-29-A B1): labels sit in a tidy stack on the right with a leader line
    // to the dot on the path, instead of floating over the centerline where the top (Entry) label was clipped.
    private static let calloutW: CGFloat = 104, calloutH: CGFloat = 48, viewW: CGFloat = 344, viewH: CGFloat = 360

    private var placed: [PlacedLabel] {
        let cx = Self.viewW - Self.calloutW / 2 - 8            // callout center x, right-aligned
        let topMin = Self.calloutH / 2 + 52                    // clear of the chip + top note
        let botMax = Self.viewH - Self.calloutH / 2 - 36       // clear of the legend
        let sorted = labels.sorted { $0.point.y < $1.point.y }
        let n = sorted.count
        guard n > 0 else { return [] }
        // Evenly distribute the cards in the available band (in path order) so they NEVER overlap; each leader
        // line still points to its true projected dot. Centered as a group between topMin and botMax.
        let span = max(0, botMax - topMin)
        let step = n > 1 ? min(Self.calloutH + 8, span / CGFloat(n - 1)) : 0
        let start = topMin + (span - step * CGFloat(n - 1)) / 2
        return sorted.enumerated().map { i, lab -> PlacedLabel in
            let y = start + step * CGFloat(i)
            return PlacedLabel(label: lab, center: CGPoint(x: cx, y: y),
                               anchor: CGPoint(x: cx - Self.calloutW / 2, y: y))   // leader attaches to left edge
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Lane3DRepresentable(result: result, rightHanded: rightHanded, labels: $labels)
            // Leader lines + a dot at each projected point on the path.
            Canvas { ctx, _ in
                for p in placed {
                    let dot: CGPoint = p.label.point
                    var line = Path()
                    line.move(to: p.anchor)
                    line.addLine(to: dot)
                    ctx.stroke(line, with: .color(p.label.color.opacity(0.7)), lineWidth: 1)
                    let rect = CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)
                    ctx.fill(Path(ellipseIn: rect), with: .color(p.label.color))
                }
            }
            ForEach(placed) { p in
                LaneGlassLabel(label: p.label).frame(width: Self.calloutW).position(p.center)
            }
            resultChip.padding(8)
            VStack { Spacer(); legend.padding(8) }
            // DEC-127: the far-lane note sits at the TOP of the lane view (below the result chip), never over the
            // middle where it would hide the measured callouts (matches shot_card_state_far_lane_not_read.png).
            if farLaneNotRead {
                VStack(spacing: 0) { farLaneNote.padding(.top, 38).padding(.horizontal, 10); Spacer() }
            }
        }
        .frame(width: Self.viewW, height: Self.viewH)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    private var resultChip: some View {
        let (txt, color): (String, Color) = {
            if farLaneNotRead { return ("Result not read", LS.textSecondary) }
            switch result.insightsState {
            case "strike_repeat": return ("Strike", LS.positive)
            case "pins_unknown", "no_reliable_data": return ("Result not read", LS.textSecondary)
            default: return ("Not a strike", LS.textPrimary)
            }
        }()
        return Text(txt).font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(LS.blue, "Target"); legendDot(Color(hex: 0x00EB92), "Your ball")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
        }
    }

    private var farLaneNote: some View {
        // Prefer the server's honest reason: the far lane is withheld because it isn't validated yet (DEC-065),
        // which is NOT the same as a camera-position problem — the "move your camera" copy only applies when
        // that's actually why. Fall back to the camera-spot copy when no reason was given.
        // Concise, honest copy — entry/breakpoint are gated by policy (DEC-065), not a camera problem. The full
        // reason lives on the outcome row; the card shows a one-liner so it doesn't dominate the lane view.
        return VStack(alignment: .leading, spacing: 2) {
            Text("Back lane not measured yet").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text("Entry, breakpoint and pins aren't read yet — coaching uses what was measured.")
                .font(.system(size: 10)).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
    }
}

/// A right-side callout: the projected label plus where its glass card sits and where its leader line attaches.
private struct PlacedLabel: Identifiable {
    let label: ProjectedLabel
    let center: CGPoint
    let anchor: CGPoint
    var id: String { label.id }
}

/// A projected pinned label: its screen point (in the lane view's coordinates) + text + accent.
struct ProjectedLabel: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let color: Color
    let point: CGPoint
}

private struct LaneGlassLabel: View {
    let label: ProjectedLabel
    var body: some View {
        VStack(spacing: 1) {
            Text(label.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(label.color)
            Text(label.value).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x001018).opacity(0.74), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(label.color.opacity(0.8), lineWidth: 1))
    }
}

// MARK: - SceneKit scene

private struct Lane3DRepresentable: UIViewRepresentable {
    let result: ShotResult
    let rightHanded: Bool
    @Binding var labels: [ProjectedLabel]

    /// Procedural lane wood: 39 warm-brown board stripes (deterministic per-board jitter) + seams + faint grain,
    /// mapped across the lane width so the boards read as vertical lanes down the view (matches lane3d.html wood).
    static let woodTexture: UIImage = {
        let W = 256, H = 1024, boards = 39
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { c in
            let ctx = c.cgContext
            let bw = CGFloat(W) / CGFloat(boards)
            for b in 0..<boards {
                let j = CGFloat(b * 53 % 13) / 13.0 - 0.5                   // -0.5…0.5, deterministic
                ctx.setFillColor(UIColor(red: 0.60 + j * 0.10, green: 0.40 + j * 0.07,
                                         blue: 0.22 + j * 0.05, alpha: 1).cgColor)
                ctx.fill(CGRect(x: CGFloat(b) * bw, y: 0, width: bw + 1, height: CGFloat(H)))
                ctx.setFillColor(UIColor(red: 0.18, green: 0.10, blue: 0.035, alpha: 0.5).cgColor)
                ctx.fill(CGRect(x: CGFloat(b) * bw, y: 0, width: 0.8, height: CGFloat(H)))   // board seam
            }
            ctx.setStrokeColor(UIColor(red: 0.43, green: 0.24, blue: 0.10, alpha: 0.06).cgColor)
            ctx.setLineWidth(1)
            var y: CGFloat = 0
            while y < CGFloat(H) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: CGFloat(W), y: y)); y += 7 }
            ctx.strokePath()
        }
    }()

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: CGRect(x: 0, y: 0, width: 344, height: 360))
        v.backgroundColor = UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 1)
        v.antialiasingMode = .multisampling2X
        v.isUserInteractionEnabled = false
        v.scene = buildScene()
        DispatchQueue.main.async { self.project(in: v) }   // after layout → pin the glass labels
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        v.scene = buildScene()
        DispatchQueue.main.async { self.project(in: v) }
    }

    // MARK: scene graph

    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.008, green: 0.039, blue: 0.078, alpha: 1)   // 0x020a14
        scene.rootNode.addChildNode(laneNode(center: true))
        // Neighbor lanes, dimmed (0x3a3a3a). Pitch = lane + 2 gutters + cap ≈ 5.0 ft.
        let pitchFt = 41.5 / 12.0 + 2 * 0.77 + 0.42
        for s in [-1.0, 1.0] {
            let n = laneNode(center: false); n.position.x = Float(s * pitchFt); scene.rootNode.addChildNode(n)
        }
        gutterNodes().forEach(scene.rootNode.addChildNode)
        scene.rootNode.addChildNode(foulLineNode())
        arrowsNode().forEach(scene.rootNode.addChildNode)
        approachDotsNode().forEach(scene.rootNode.addChildNode)
        pinsNode().forEach(scene.rootNode.addChildNode)
        if let tl = targetLineNode() { scene.rootNode.addChildNode(tl) }
        ballPathNodes().forEach(scene.rootNode.addChildNode)

        // Camera matches the design render (lane3d.html / shots.json): 22 ft behind the foul, 9.5 ft up, looking
        // 33 ft down the lane, 14.5° vertical FOV (our z is negated vs the HTML: pins are at −60).
        let cam = SCNCamera(); cam.fieldOfView = 15; cam.projectionDirection = .vertical; cam.zFar = 400
        cam.wantsHDR = true; cam.bloomIntensity = 0.5; cam.bloomBlurRadius = 4; cam.bloomThreshold = 0.75
        let camNode = SCNNode(); camNode.camera = cam
        camNode.position = SCNVector3(0, 11, 26)
        camNode.look(at: SCNVector3(0, 0, -34))
        scene.rootNode.addChildNode(camNode)

        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient
        amb.light!.intensity = 650; amb.light!.color = UIColor(red: 0.66, green: 0.77, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(amb)
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .spot
        key.light!.intensity = 1500; key.light!.color = UIColor(red: 1, green: 0.95, blue: 0.86, alpha: 1)
        key.light!.spotInnerAngle = 30; key.light!.spotOuterAngle = 80
        key.position = SCNVector3(0, 22, 6); key.look(at: SCNVector3(0, 0, -28))
        scene.rootNode.addChildNode(key)
        return scene
    }

    private func laneNode(center: Bool) -> SCNNode {
        let w = CGFloat(41.5 / 12.0), l = CGFloat(66)
        let plane = SCNBox(width: w, height: 0.02, length: l, chamferRadius: 0)
        let m = SCNMaterial()
        if center {
            m.diffuse.contents = Self.woodTexture   // procedural 39-board wood (grain + seams), matches the render
            m.diffuse.wrapT = .clamp; m.diffuse.wrapS = .clamp
            m.roughness.contents = 0.3; m.metalness.contents = 0.0
        } else {
            m.diffuse.contents = UIColor(white: 0.227, alpha: 1)   // 0x3a3a3a dimmed neighbor bed
        }
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane); n.position = SCNVector3(0, 0, -30); n.opacity = center ? 1 : 0.55
        return n
    }

    /// Dark gutter channels either side of the center lane (half-round approximated by a dark box).
    private func gutterNodes() -> [SCNNode] {
        let laneHalf = CGFloat(41.5 / 12.0) / 2, gut = CGFloat(0.77)
        return [-1.0, 1.0].map { s in
            let box = SCNBox(width: gut, height: 0.14, length: 62, chamferRadius: 0.05)
            box.firstMaterial?.diffuse.contents = UIColor(red: 0.043, green: 0.067, blue: 0.098, alpha: 1)  // 0x0b1119
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(Float(Double(s) * Double(laneHalf + gut / 2)), -0.05, -31); return n
        }
    }

    private func foulLineNode() -> SCNNode {
        let box = SCNBox(width: CGFloat(41.5 / 12.0 + 2 * 0.77), height: 0.03, length: 0.12, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor(red: 0.102, green: 0.039, blue: 0.024, alpha: 1)   // 0x1a0a06
        let n = SCNNode(geometry: box); n.position = SCNVector3(0, 0.012, 0); return n
    }

    private func arrowsNode() -> [SCNNode] {
        // Seven arrows on boards 5..35, staggered in z (center arrow deepest), dark on the wood — like the render.
        [5.0, 10, 15, 20, 25, 30, 35].map { b in
            let p = SCNPyramid(width: 0.16, height: 0.015, length: 0.55)
            p.firstMaterial?.diffuse.contents = UIColor(red: 0.165, green: 0.086, blue: 0.031, alpha: 1)  // 0x2a1608
            p.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: p)
            let zStag = 13.0 + (4.0 - abs(b - 20.0) / 5.0) * 0.8
            n.position = SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.015, Float(-zStag))
            return n
        }
    }

    private func approachDotsNode() -> [SCNNode] {
        [3.0, 5, 8, 11, 14, 26, 29, 32, 35, 37].map { b in
            let s = SCNCylinder(radius: 0.05, height: 0.012)
            s.firstMaterial?.diffuse.contents = UIColor(red: 0.165, green: 0.086, blue: 0.031, alpha: 1)  // 0x2a1608
            s.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.012, 7)   // 7 ft dots
            return n
        }
    }

    private func pinsNode() -> [SCNNode] {
        // Standard 10-pin triangle, head pin at lane center, 1 ft spacing, rows 0.866 ft apart toward the pit.
        // True-scale pin ≈ 1.25 ft tall; a white body + a red band approximates the pin silhouette.
        let layout: [(row: Int, col: Double)] = [(0, 0), (1, -0.5), (1, 0.5), (2, -1), (2, 0), (2, 1),
                                                 (3, -1.5), (3, -0.5), (3, 0.5), (3, 1.5)]
        var out: [SCNNode] = []
        for r in layout {
            let x = Float(rightHanded ? r.col : -r.col)
            let z = Float(-60.0 - Double(r.row) * 0.866)
            let body = SCNCapsule(capRadius: 0.085, height: 1.15)
            body.firstMaterial?.diffuse.contents = UIColor(red: 0.969, green: 0.973, blue: 0.984, alpha: 1)  // 0xf7f8fb
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(x, 0.575, z); out.append(bn)
            let band = SCNCylinder(radius: 0.088, height: 0.07)
            band.firstMaterial?.diffuse.contents = UIColor(red: 0.816, green: 0.149, blue: 0.227, alpha: 1)  // 0xd0263a
            let dn = SCNNode(geometry: band); dn.position = SCNVector3(x, 0.78, z); out.append(dn)
        }
        return out
    }

    /// The smoothed ball path (path_fit) as a GLOWING green tube: a thin bright core + a wider translucent glow,
    /// built as a chain of oriented cylinders (SceneKit has no polyline tube). HDR bloom on the camera makes it glow.
    private func ballPathNodes() -> [SCNNode] {
        guard let pts = result.pathFit?.points, pts.count >= 2 else { return [] }
        let verts = pts.compactMap { p -> SCNVector3? in
            guard let z = p.z_ft, let b = p.board else { return nil }
            return SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.06, Float(-z))
        }
        guard verts.count >= 2 else { return [] }
        return tube(verts, radius: 0.10, color: UIColor(red: 0, green: 0.92, blue: 0.57, alpha: 1), opacity: 0.28)
             + tube(verts, radius: 0.035, color: UIColor(red: 0.49, green: 1, blue: 0.78, alpha: 1), opacity: 1)
    }

    /// Target line: intended laydown → pocket (board 17.5 at the head pin) as a bright-blue tube.
    private func targetLineNode() -> SCNNode? {
        let lay = result.keyPoints["laydown"]?.board ?? result.metrics.first(where: { $0.0 == "laydown_board" })?.1.value
        guard let lay else { return nil }
        let a = SCNVector3(Float(ShotLaneView.xFt(lay, rightHanded: rightHanded)), 0.05, 0)
        let b = SCNVector3(Float(ShotLaneView.xFt(17.5, rightHanded: rightHanded)), 0.05, -60)
        let g = SCNNode()
        tube([a, b], radius: 0.05, color: UIColor(red: 0.118, green: 0.565, blue: 1, alpha: 1), opacity: 0.95)  // 0x1e90ff
            .forEach(g.addChildNode)
        return g
    }

    /// A tube along a polyline = one oriented cylinder per segment (constant-shaded; emission via HDR bloom).
    private func tube(_ verts: [SCNVector3], radius: CGFloat, color: UIColor, opacity: CGFloat) -> [SCNNode] {
        var nodes: [SCNNode] = []
        for i in 0..<(verts.count - 1) {
            let a = verts[i], b = verts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let len = CGFloat(sqrtf(dx * dx + dy * dy + dz * dz))
            if len < 1e-4 { continue }
            let cyl = SCNCylinder(radius: radius, height: len)
            let m = SCNMaterial(); m.diffuse.contents = color; m.emission.contents = color
            m.lightingModel = .constant; m.isDoubleSided = true
            m.transparency = opacity; cyl.firstMaterial = m
            let n = SCNNode(geometry: cyl)
            n.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            // orient the cylinder's +y axis along the segment
            n.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            nodes.append(n)
        }
        return nodes
    }

    // MARK: project the 4 pinned labels to screen

    private func project(in v: SCNView) {
        guard v.bounds.width > 1 else { return }
        let rh = rightHanded
        func screen(_ b: Double?, _ z: Double) -> CGPoint? {
            guard let b else { return nil }
            let w = SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rh)), 0.1, Float(-z))
            let p = v.projectPoint(w)
            guard p.z > 0, p.z < 1 else { return nil }
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }
        let kp = result.keyPoints
        func m(_ k: String) -> Double? { result.metrics.first(where: { $0.0 == k })?.1.value }
        var out: [ProjectedLabel] = []
        let notRead = result.coachLane?.status == "not_read"
        if let ld = kp["laydown"]?.board ?? m("laydown_board"), let pt = screen(ld, kp["laydown"]?.z_ft ?? 0) {
            out.append(.init(id: "laydown", title: "Laydown", value: "\(Int(ld.rounded()))", color: .white, point: pt))
        }
        if let ar = kp["arrows"]?.board ?? m("arrows_board"), let pt = screen(ar, kp["arrows"]?.z_ft ?? 15) {
            out.append(.init(id: "arrows", title: "Arrows", value: "\(Int(ar.rounded()))",
                             color: Color(hex: 0x00EB92), point: pt))
        }
        if !notRead, let bp = kp["breakpoint"]?.board ?? m("breakpoint_board"),
           let pt = screen(bp, kp["breakpoint"]?.z_ft ?? m("breakpoint_distance") ?? 40) {
            out.append(.init(id: "breakpoint", title: "Breakpoint", value: "\(Int(bp.rounded()))",
                             color: Color(hex: 0xF5CD31), point: pt))
        }
        if !notRead, let en = kp["entry"]?.board ?? m("entry_board"), let pt = screen(en, kp["entry"]?.z_ft ?? 59.44) {
            let ang = kp["entry"]?.angle_deg ?? m("entry_angle")
            out.append(.init(id: "entry", title: "Entry", value: ang.map { "\(Int(en.rounded())) · \(String(format: "%.1f°", $0))" } ?? "\(Int(en.rounded()))",
                             color: Color(hex: 0xFA923C), point: pt))
        }
        if out != labels { labels = out }
    }
}
