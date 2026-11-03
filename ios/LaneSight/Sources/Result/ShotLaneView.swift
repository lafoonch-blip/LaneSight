import SwiftUI
import WebKit

/// DEC-088/090/127 Shot card lane view. Renders the SAME 3D scene as the design (`02_DESIGN/target_state/
/// lane_render/lane3d.html`) in a WKWebView, bundled with three.js locally (no network → works in airplane mode).
/// The shot's measured data is passed as JSON (dense ball path to the last measured distance, target line, key
/// points → markers, camera, and a `cut` that STOPS the path + dims the lane past it when the far lane isn't
/// measured — so we never draw a hook into the pins we didn't measure). The scene draws the lane, wood, arrows,
/// pins, gutters, dimmed neighbors, the glowing path, the target corridor and the marker rings with its own
/// camera + materials; SwiftUI overlays the result chip, legend, the top far-lane note and the glass callouts
/// (pinned to the scene's own projected marker points, read back from the page).
struct ShotLaneView: View {
    let result: ShotResult
    @State private var pts: [String: CGPoint] = [:]      // scene-projected marker points, in the W×H card space

    private static let viewW: CGFloat = 344, viewH: CGFloat = 360
    private static let calloutW: CGFloat = 116, calloutH: CGFloat = 50
    private var farLaneNotRead: Bool { result.coachLane?.status == "not_read" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShotLaneWebView(dataJSON: Self.sceneData(result), w: Int(Self.viewW), h: Int(Self.viewH), pts: $pts)
            // Leader lines + a dot at each projected marker on the path.
            Canvas { ctx, _ in
                for p in placed {
                    var line = Path(); line.move(to: p.anchor); line.addLine(to: p.label.point)
                    ctx.stroke(line, with: .color(p.label.color.opacity(0.7)), lineWidth: 1)
                    let r = CGRect(x: p.label.point.x - 2.5, y: p.label.point.y - 2.5, width: 5, height: 5)
                    ctx.fill(Path(ellipseIn: r), with: .color(p.label.color))
                }
            }
            ForEach(placed) { p in LaneGlassLabel(label: p.label).frame(width: Self.calloutW).position(p.center) }
            resultChip.padding(8)
            VStack { Spacer(); legend.padding(8) }
            if farLaneNotRead {
                VStack(spacing: 0) { farLaneNote.padding(.top, 38).padding(.horizontal, 10); Spacer() }
            }
        }
        .frame(width: Self.viewW, height: Self.viewH)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    // MARK: callouts (built from the scene's projected marker points + the measured values)

    /// Markers the lane view can show, in path order. Laydown + Arrows whenever measured; Breakpoint + Entry only
    /// when the far lane is NOT gated (DEC-065). Values + "board · …" sub-labels mirror the design callouts.
    private var projectedLabels: [ProjectedLabel] {
        func m(_ k: String) -> Double? { result.metrics.first { $0.0 == k }?.1.value }
        let kp = result.keyPoints
        var out: [ProjectedLabel] = []
        func add(_ key: String, _ title: String, _ board: Double?, _ sub: String, _ color: Color) {
            guard let board, let pt = pts[key] else { return }
            out.append(.init(id: key, title: title, value: "\(Int(board.rounded()))", sub: sub, color: color, point: pt))
        }
        add("laydown", "Laydown", kp["laydown"]?.board ?? m("laydown_board"), "board", .white)
        let tgtArrows = result.recommendation?.move_target   // intent at the arrows, if any
        add("arrows", "Arrows", kp["arrows"]?.board ?? m("arrows_board"),
            tgtArrows.map { "board · target \(Int($0.rounded()))" } ?? "board", Color(hex: 0x00EB92))
        if !farLaneNotRead {
            let bpFt = kp["breakpoint"]?.z_ft ?? m("breakpoint_distance")
            add("bp", "Breakpoint", kp["breakpoint"]?.board ?? m("breakpoint_board"),
                bpFt.map { "board · \(Int($0.rounded())) ft" } ?? "board", Color(hex: 0xF5CD31))
            let ang = kp["entry"]?.angle_deg ?? m("entry_angle")
            add("entry", "Entry point", kp["entry"]?.board ?? m("entry_board"),
                ang.map { String(format: "board · %.1f°", $0) } ?? "board", Color(hex: 0xFA923C))
        }
        return out
    }

    /// Place the callouts in the right column, evenly distributed so they never overlap; each leader still points
    /// to its true projected marker.
    private var placed: [PlacedLabel] {
        let labels = projectedLabels
        let cx = Self.viewW - Self.calloutW / 2 - 8
        let topMin = Self.calloutH / 2 + 52, botMax = Self.viewH - Self.calloutH / 2 - 36
        let sorted = labels.sorted { $0.point.y < $1.point.y }
        let n = sorted.count
        guard n > 0 else { return [] }
        let span = max(0, botMax - topMin)
        let step = n > 1 ? min(Self.calloutH + 6, span / CGFloat(n - 1)) : 0
        let start = topMin + (span - step * CGFloat(n - 1)) / 2
        return sorted.enumerated().map { i, lab in
            let y = start + step * CGFloat(i)
            return PlacedLabel(label: lab, center: CGPoint(x: cx, y: y),
                               anchor: CGPoint(x: cx - Self.calloutW / 2, y: y))
        }
    }

    // MARK: overlays

    private var resultChip: some View {
        let (txt, color): (String, Color) = {
            if farLaneNotRead { return ("Result not read", LS.textSecondary) }
            switch result.insightsState {
            case "strike_repeat": return ("Strike", LS.positive)
            case "pins_unknown", "no_reliable_data": return ("Result not read", LS.textSecondary)
            default: return ("Not a strike", LS.textPrimary)
            }
        }()
        return Text(txt).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5).background(.ultraThinMaterial, in: Capsule())
    }

    private var legend: some View {
        HStack(spacing: 10) { legendDot(LS.blue, "Target"); legendDot(Color(hex: 0x00EB92), "Your ball") }
            .padding(.horizontal, 10).padding(.vertical, 5).background(.ultraThinMaterial, in: Capsule())
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(.white) }
    }

    private var farLaneNote: some View {
        VStack(alignment: .leading, spacing: 2) {
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

    // MARK: scene DATA (the JSON the lane3d scene draws from)

    /// Build the scene DATA in the HTML's native frame (z = ft down the lane, foul 0 → pins 60; board 1 = right
    /// gutter, matching the record's absolute boards). `cut` stops the path + dims the lane when the far lane
    /// isn't measured — the honesty fix so the ball path never hooks into pins we didn't read.
    static func sceneData(_ r: ShotResult) -> String {
        func m(_ k: String) -> Double? { r.metrics.first { $0.0 == k }?.1.value }
        let kp = r.keyPoints
        let gated = r.coachLane?.status == "not_read"
        // dense measured path (to the last measured distance; `cut` trims it in-scene)
        var act: [[Double]] = []
        for p in (r.pathFit?.points ?? []) { if let z = p.z_ft, let b = p.board { act.append([z, b]) } }
        var data: [String: Any] = [
            "cam": [0, 9.5, -22], "look": [0, 0, 33], "fov": 14.5,
            "act": [[0, 20, 0], [30, 14, 0], [60, 17.5, "e", 4.0]],   // fallback anchors if no dense path
            "marks": [] as [[String: Any]],
        ]
        if act.count > 1 { data["actDense"] = act }
        // DEC-127 honesty: far-lane gated ⇒ stop the path mid-lane (matches lane_render_far_lane_not_read: cut 32).
        if gated { data["cut"] = 32.0 }
        // target line: laydown → arrows target → pocket (only when we have an intent to aim at)
        if let lay = kp["laydown"]?.board ?? m("laydown_board"), let tgt = r.recommendation?.move_target {
            data["tgt"] = [[0, lay, -0.3], [15, tgt, -0.3], [60, 17.5, "e", 4.5]]
        }
        // markers → rings in the scene; the SwiftUI callouts pin to their projected points
        var marks: [[String: Any]] = []
        if let b = kp["laydown"]?.board ?? m("laydown_board") { marks.append(["k": "laydown", "z": 0, "b": b, "c": "#cfd8e6"]) }
        if let b = kp["arrows"]?.board ?? m("arrows_board") { marks.append(["k": "arrows", "z": 15, "b": b, "c": "#00eb92"]) }
        if !gated {
            if let b = kp["breakpoint"]?.board ?? m("breakpoint_board") {
                marks.append(["k": "bp", "z": kp["breakpoint"]?.z_ft ?? m("breakpoint_distance") ?? 43, "b": b, "c": "#f5cd31"]) }
            if let b = kp["entry"]?.board ?? m("entry_board") { marks.append(["k": "entry", "z": 59.4, "b": b, "c": "#fa923c"]) }
        }
        data["marks"] = marks
        return (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

private struct PlacedLabel: Identifiable { let label: ProjectedLabel; let center: CGPoint; let anchor: CGPoint; var id: String { label.id } }
struct ProjectedLabel: Identifiable, Equatable {
    let id: String; let title: String; let value: String; let sub: String; let color: Color; let point: CGPoint
}

private struct LaneGlassLabel: View {
    let label: ProjectedLabel
    var body: some View {
        VStack(spacing: 1) {
            Text(label.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(label.color)
            Text(label.value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text(label.sub).font(.system(size: 8)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity)
        .background(Color(hex: 0x001018).opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(label.color.opacity(0.8), lineWidth: 1))
    }
}

// MARK: - WKWebView host for the bundled lane3d scene

/// Serves the bundled `LaneRender/` web assets (lane_card.html + three.js) over a custom scheme so the ES-module
/// importmap resolves offline (no file:// CORS, no network — airplane-mode safe).
final class LaneSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lanerender"
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let root = Bundle.main.url(forResource: "LaneRender", withExtension: nil) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let rel = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = root.appendingPathComponent(rel.isEmpty ? "lane_card.html" : rel)
        guard let data = try? Data(contentsOf: file) else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        let mime = rel.hasSuffix(".js") ? "text/javascript" : (rel.hasSuffix(".html") || rel.isEmpty ? "text/html" : "application/octet-stream")
        let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct ShotLaneWebView: UIViewRepresentable {
    let dataJSON: String
    let w: Int
    let h: Int
    @Binding var pts: [String: CGPoint]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(LaneSchemeHandler(), forURLScheme: LaneSchemeHandler.scheme)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: w, height: h), configuration: cfg)
        wv.isOpaque = true
        wv.backgroundColor = UIColor(red: 0.008, green: 0.039, blue: 0.078, alpha: 1)   // 0x020a14 scene bg
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = context.coordinator
        load(wv, context: context)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.lastData != dataJSON { load(wv, context: context) }
    }

    private func load(_ wv: WKWebView, context: Context) {
        context.coordinator.lastData = dataJSON
        let enc = dataJSON.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard let url = URL(string: "\(LaneSchemeHandler.scheme)://card/lane_card.html?w=\(w)&h=\(h)&d=\(enc)") else { return }
        wv.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ShotLaneWebView
        var lastData = ""
        init(_ p: ShotLaneWebView) { parent = p }
        func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) { poll(wv, 0) }
        private func poll(_ wv: WKWebView, _ n: Int) {
            wv.evaluateJavaScript("window.__done===true") { done, _ in
                if (done as? Bool) == true {
                    wv.evaluateJavaScript("window.__t||0") { t, _ in
                        if let ms = t as? Int { NSLog("LANE_RENDER_MS %d", ms) }   // time to first frame (DEC-127)
                    }
                    wv.evaluateJavaScript("JSON.stringify(window.__pts||{})") { v, _ in
                        guard let s = v as? String, let d = s.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [Double]] else { return }
                        var out: [String: CGPoint] = [:]
                        for (k, xy) in obj where xy.count == 2 { out[k] = CGPoint(x: xy[0], y: xy[1]) }
                        DispatchQueue.main.async { if out != self.parent.pts { self.parent.pts = out } }
                    }
                } else if n < 60 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.poll(wv, n + 1) }
                }
            }
        }
    }
}
