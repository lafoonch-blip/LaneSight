import Foundation

// MARK: - API response models
//
// The LaneSight OpenAPI contract declares most response bodies as free-form objects, so these
// Codable models intentionally decode only the fields the app uses and tolerate missing ones.
// Every number is decoded as Double so an int / float / null from the server never breaks decoding.
// NOTHING here is a sample or default metric value — all displayed numbers come from the live API.

struct HealthResponse: Codable {
    let status: String?
    let versions: [String: String]?
    let config: HealthConfig?
}

struct HealthConfig: Codable {
    let mode: String?
    let dev_insecure: Bool?
    let db_url_present: Bool?
    let service_role_present: Bool?
    let jwks_url_present: Bool?
}

struct SessionResponse: Codable {
    let id: String
}

struct CreateShotResponse: Codable {
    let shot_id: String
    let job_id: String
}

struct JobResponse: Codable {
    let id: String
    let kind: String?
    let state: String          // queued | running | done | failed
    let reason: String?
    let timings: [String: Double]?
}

struct ShotResponse: Codable {
    let id: String?
    let record: ShotRecord?
}

struct ShotRecord: Codable {
    let shot_id: String?
    let metrics: [String: Metric]?
}

struct Metric: Codable {
    let metric: String?
    let value: Double?
    let unit: String?
    let status: String?
    let note: String?
    let confidence: Double?
}

struct ScoreResponse: Codable {
    let eligible: Bool?
    let score: Double?
    let tier: String?
    let s_perf: Double?
    let a_acc: Double?
    let c_cons: Double?
    let p_power: Double?
    let eligibility: [String: Eligibility]?
    let formula_version: String?
    let label: String?
}

struct Eligibility: Codable {
    let have: Int?
    let need: Int?
    let met: Bool?
}

// MARK: - Request payloads

struct ShotIntent {
    var arrowsBoard: Double?
    var breakpointBoard: Double?
}

struct ShotMetadata {
    var handed: String          // "R" / "L"
    var captureMode: String     // "shot" / "form"
    var source: String          // "live"
    var intent: ShotIntent

    /// Builds the exact JSON string the API expects for the `metadata` multipart field.
    /// Intent values are emitted explicitly as `null` when absent (matches the contract).
    func jsonString() -> String {
        let intentDict: [String: Any] = [
            "arrows_board": intent.arrowsBoard as Any? ?? NSNull(),
            "breakpoint_board": intent.breakpointBoard as Any? ?? NSNull(),
        ]
        let dict: [String: Any] = [
            "handed": handed,
            "capture_mode": captureMode,
            "source": source,
            "intent": intentDict,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - Display ordering

enum MetricDisplay {
    /// Preferred ordering for the result screen; any metric not listed is appended alphabetically.
    static let preferredOrder: [String] = [
        "ball_speed", "speed_early", "speed_late",
        "laydown_board", "arrows_board", "board_at_7ft", "breakpoint_board", "entry_board",
        "launch_angle", "entry_angle", "angle_at_arrows",
        "loft", "rev_rate", "axis_rotation", "axis_tilt", "tilt",
    ]

    /// Returns (name, metric) pairs in a stable, human-friendly order.
    static func ordered(_ metrics: [String: Metric]) -> [(String, Metric)] {
        let known = preferredOrder.compactMap { name in metrics[name].map { (name, $0) } }
        let rest = metrics.keys
            .filter { !preferredOrder.contains($0) }
            .sorted()
            .compactMap { name in metrics[name].map { (name, $0) } }
        return known + rest
    }

    /// "ball_speed" -> "Ball Speed"
    static func humanize(_ name: String) -> String {
        name.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
