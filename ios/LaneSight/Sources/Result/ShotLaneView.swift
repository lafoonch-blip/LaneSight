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
    private static let calloutW: CGFloat = 96, calloutH: CGFloat = 32, viewW: CGFloat = 344, viewH: CGFloat = 360

    private var placed: [PlacedLabel] {
        let cx = Self.viewW - Self.calloutW / 2 - 8           // callout center x, right-aligned
        let topMin = Self.calloutH / 2 + 30                    // clear of the result chip
        let botMax = Self.viewH - Self.calloutH / 2 - 36       // clear of the legend
        let spacing = Self.calloutH + 6
        var cursor = topMin
        return labels.sorted { $0.point.y < $1.point.y }.map { lab -> PlacedLabel in
            let y = min(max(lab.point.y, cursor), botMax)
            cursor = y + spacing
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
                    var line = Path(); line.move(to: p.anchor); line.addLine(to: p.label.point)
                    ctx.stroke(line, with: .color(p.label.color.opacity(0.7)), lineWidth: 1)
                    let d: CGFloat = 4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.label.point.x - d/2, y: p.label.point.y - d/2, width: d, height: d)),
                             with: .color(p.label.color))
                }
            }
            ForEach(placed) { p in
                LaneGlassLabel(label: p.label).frame(width: Self.calloutW).position(p.center)
            }
            resultChip.padding(8)
            VStack { Spacer(); legend.padding(8) }
            if farLaneNotRead { farLaneNote }
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
        let reason = result.capture_quality?.reason
        return VStack(spacing: 2) {
            Text("Back lane not shown yet").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(reason ?? "Breakpoint, entry and pins need the full lane")
                .font(.system(size: 10)).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center).lineLimit(3)
        }
        .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 240)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        scene.rootNode.addChildNode(laneNode(center: true))
        // Neighbor lanes, dimmed.
        for s in [-1.0, 1.0] {
            let n = laneNode(center: false); n.position.x = Float(s * 41.5 / 12.0 * 1.06); scene.rootNode.addChildNode(n)
        }
        scene.rootNode.addChildNode(foulLineNode())
        arrowsNode().forEach(scene.rootNode.addChildNode)
        approachDotsNode().forEach(scene.rootNode.addChildNode)
        pinsNode().forEach(scene.rootNode.addChildNode)
        if let tl = targetLineNode() { scene.rootNode.addChildNode(tl) }
        if let bp = ballPathNode() { scene.rootNode.addChildNode(bp) }

        // Camera: 30 ft behind the foul line, 10 ft up, looking 15.5 ft down the lane, 16° vertical FOV.
        let cam = SCNCamera(); cam.fieldOfView = 16; cam.projectionDirection = .vertical; cam.zFar = 400
        let camNode = SCNNode(); camNode.camera = cam
        camNode.position = SCNVector3(0, 10, 30)
        camNode.look(at: SCNVector3(0, 0, -15.5))
        scene.rootNode.addChildNode(camNode)

        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient
        amb.light!.intensity = 700; scene.rootNode.addChildNode(amb)
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional
        key.light!.intensity = 600; key.position = SCNVector3(0, 20, 20); key.look(at: SCNVector3(0, 0, -30))
        scene.rootNode.addChildNode(key)
        return scene
    }

    private func laneNode(center: Bool) -> SCNNode {
        let w = CGFloat(41.5 / 12.0), l = CGFloat(66)
        let plane = SCNBox(width: w, height: 0.02, length: l, chamferRadius: 0)
        let m = SCNMaterial()
        m.diffuse.contents = center ? UIColor(red: 0.78, green: 0.62, blue: 0.38, alpha: 1)
                                     : UIColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1)
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane); n.position = SCNVector3(0, 0, -30); n.opacity = center ? 1 : 0.35
        return n
    }

    private func foulLineNode() -> SCNNode {
        let box = SCNBox(width: CGFloat(41.5 / 12.0), height: 0.03, length: 0.2, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.3, blue: 0.36, alpha: 1)
        let n = SCNNode(geometry: box); n.position = SCNVector3(0, 0.01, 0); return n
    }

    private func arrowsNode() -> [SCNNode] {
        [5.0, 10, 15, 20, 25, 30, 35].map { b in
            let p = SCNPyramid(width: 0.18, height: 0.02, length: 0.5)
            p.firstMaterial?.diffuse.contents = UIColor(white: 0.9, alpha: 0.9)
            let n = SCNNode(geometry: p)
            n.position = SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.02, -15)
            return n
        }
    }

    private func approachDotsNode() -> [SCNNode] {
        [10.0, 15, 20, 25, 30].map { b in
            let s = SCNSphere(radius: 0.05); s.firstMaterial?.diffuse.contents = UIColor(white: 0.85, alpha: 0.8)
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.02, 2.5)
            return n
        }
    }

    private func pinsNode() -> [SCNNode] {
        // Standard 10-pin triangle, head pin at board 20, 12 in spacing, rows 1 ft apart toward the pit.
        let spacing = 12.0 / 12.0
        let layout: [(row: Int, col: Double)] = [(0, 0), (1, -0.5), (1, 0.5), (2, -1), (2, 0), (2, 1),
                                                 (3, -1.5), (3, -0.5), (3, 0.5), (3, 1.5)]
        return layout.map { r in
            let cyl = SCNCylinder(radius: 0.08, height: 0.5)
            cyl.firstMaterial?.diffuse.contents = UIColor.white
            let n = SCNNode(geometry: cyl)
            let x = r.col * spacing
            n.position = SCNVector3(Float(rightHanded ? x : -x), 0.25, Float(-60.0 - Double(r.row) * spacing))
            return n
        }
    }

    /// The smoothed ball path (path_fit) as a thin green line. Drawn only to the last measured distance.
    private func ballPathNode() -> SCNNode? {
        guard let pts = result.pathFit?.points, pts.count >= 2 else { return nil }
        let verts = pts.compactMap { p -> SCNVector3? in
            guard let z = p.z_ft, let b = p.board else { return nil }
            return SCNVector3(Float(ShotLaneView.xFt(b, rightHanded: rightHanded)), 0.04, Float(-z))
        }
        return lineNode(verts, color: UIColor(red: 0, green: 0.92, blue: 0.57, alpha: 1))
    }

    /// Target line: intended laydown → pocket (board 17.5 at the head pin). Blue.
    private func targetLineNode() -> SCNNode? {
        let lay = result.keyPoints["laydown"]?.board ?? result.metrics.first(where: { $0.0 == "laydown_board" })?.1.value
        guard let lay else { return nil }
        let a = SCNVector3(Float(ShotLaneView.xFt(lay, rightHanded: rightHanded)), 0.035, 0)
        let b = SCNVector3(Float(ShotLaneView.xFt(17.5, rightHanded: rightHanded)), 0.035, -60)
        return lineNode([a, b], color: UIColor(red: 0.12, green: 0.48, blue: 1, alpha: 1))
    }

    private func lineNode(_ verts: [SCNVector3], color: UIColor) -> SCNNode {
        let src = SCNGeometrySource(vertices: verts)
        var idx: [Int32] = []
        for i in 0..<(verts.count - 1) { idx.append(Int32(i)); idx.append(Int32(i + 1)) }
        let elem = SCNGeometryElement(indices: idx, primitiveType: .line)
        let geo = SCNGeometry(sources: [src], elements: [elem])
        let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .constant; m.isDoubleSided = true
        geo.firstMaterial = m
        let n = SCNNode(geometry: geo)
        return n
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
