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

// MARK: - Lenient scalar
//
// Several catalog / profile / oil fields can arrive as a number or a string depending on the row.
// FlexString decodes any JSON scalar into a display string so a type mismatch never breaks decoding.
struct FlexString: Codable, Equatable {
    let value: String?
    init(value: String?) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let s = try? c.decode(String.self) { value = s }
        else if let d = try? c.decode(Double.self) {
            value = (d.rounded() == d) ? String(Int(d)) : String(format: "%g", d)
        } else if let b = try? c.decode(Bool.self) { value = String(b) }
        else { value = nil }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// MARK: - Sessions

struct SessionRow: Codable, Identifiable, Equatable {
    let id: String
    let mode: String?
    let started_at: Double?
    let ended_at: Double?
    let lane_pair: FlexString?
    let oil_pattern_id: String?
}

struct EndSessionResponse: Codable {
    let session_id: String?
    let shots: Int?
    let ended_at: Double?
    let score: ScoreBrief?
}

struct ScoreBrief: Codable {
    let eligible: Bool?
    let score: Double?
    let tier: String?
}

// MARK: - Profile & sensors

struct Profile: Codable, Equatable {
    var user_id: String?
    var name: String?
    var email: String?
    var dob: String?
    var handedness: String?           // "right" | "left"
    var delivery_style: String?       // one_handed_thumb | one_handed_no_thumb | two_handed
    var approach_steps: FlexString?
    var location: String?
}

struct Sensor: Codable, Identifiable, Equatable {
    let id: String
    let user_id: String?
    let name: String?
    let `default`: Bool?
}

// MARK: - Catalog & oil

struct CatalogBall: Codable, Identifiable, Equatable {
    let id: String
    let manufacturer: String?
    let name: String?
    let coverstock: String?
    let core_type: String?
    let ls_hook: FlexString?
    let ls_length: FlexString?
    let ls_backend: FlexString?
    let image_url: String?
}

struct OilPattern: Codable, Identifiable, Equatable {
    let id: String?
    let name: String?
    let length: Double?
    let volume: Double?
    let ratio: FlexString?
    let source: String?

    // Decode numeric fields leniently so a string/number mismatch never breaks the list.
    enum CodingKeys: String, CodingKey { case id, name, length, volume, ratio, source }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        length = (try? c.decodeIfPresent(Double.self, forKey: .length)) ?? nil
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? nil
        ratio = try? c.decodeIfPresent(FlexString.self, forKey: .ratio)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
    }

    var identity: String { id ?? name ?? UUID().uuidString }
}

// MARK: - Spot check (advisory only; never blocks capture — DEC-045)

struct SpotCheckResponse: Codable {
    let blocks: Bool?
    let tips: [String]?
    let status: String?
    let version: String?
}

// MARK: - Request payloads

struct ShotIntent {
    var feetBoard: Double?
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
            "feet_board": intent.feetBoard as Any? ?? NSNull(),
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
