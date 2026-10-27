import Foundation

// MARK: - API response models
//
// The LaneSight OpenAPI contract declares most response bodies as free-form objects, so these
// Codable models intentionally decode only the fields the app uses and tolerate missing ones.
// Every number is decoded as Double so an int / float / null from the server never breaks decoding.
// NOTHING here is a sample or default metric value — all displayed numbers come from the live API.

struct HealthResponse: Codable {
    let status: String?                 // ok | degraded
    let supabase_reachable: Bool?       // true/false in live mode; null in memory mode
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

/// Target for a direct-to-Storage clip upload (POST /uploads/signed-url). The app PUTs the clip bytes to
/// `upload_url` (bypassing the API's request-size cap), then calls /shots/analyze with `path`.
struct UploadTarget: Codable {
    let path: String
    let upload_url: String
}

/// Home "next focus" (GET /me/focus, MVP-12): the single recurring issue across recent shots, or a
/// building / keep-repeating state. `detail`/`expected` reuse a shot's own recommendation copy.
struct FocusResponse: Codable, Equatable {
    let status: String?       // "ok" | "building"
    let focus: String?        // short title
    let state: String?
    let detail: String?
    let expected: String?
    let based_on: Int?
}

struct JobResponse: Codable {
    let id: String
    let kind: String?
    let state: String          // queued | running | done | failed
    let reason: String?
    let timings: [String: Double]?
    var result: ShotFooter?    // analyze-job footer (score_delta + achievement_nudges + unlocked)
}

/// The analyze job's result footer (engines.after_shot_analyzed). All optional — present only on a
/// finished analyze job. Nothing here is fabricated; absent fields stay absent.
struct ShotFooter: Codable, Equatable {
    let shot_id: String?
    let eligible: Bool?
    let score: Double?
    let score_delta: Double?
    let achievement_nudges: [AchievementNudge]?
    let unlocked: [String]?
}

struct AchievementNudge: Codable, Equatable, Identifiable {
    let achievement_id: String?
    let name: String?
    let current: Flex?
    let target: Flex?
    var id: String { achievement_id ?? name ?? UUID().uuidString }
}

struct ShotResponse: Codable {
    let id: String?
    let record: ShotRecord?
    let sequence: Int?          // 1-based shot number within its session (for the "Shot N" header)
    let capture_mode: String?
    let source: String?
}

struct ShotRecord: Codable {
    let shot_id: String?
    let metrics: [String: Metric]?
    let insights: ShotInsights?
    // Form-analysis fields (present only when the shot was captured in FORM mode). All optional so a
    // ball shot — which never carries them — decodes unchanged. `form_version` being non-nil is the
    // fallback signal that this record is a form result; `status` is the top-level form status
    // ("ok" | "unavailable") and `view` is the detected camera angle.
    let form_version: String?
    let view: String?
    let status: String?
    let fps: Double?
    // Capture quality (GUARDRAILS 3.7 B): far_lane == "limited" drives the camera-spot banner; `reason`
    // is the honest one-line explanation. `source` distinguishes an uploaded clip from a live shot.
    let capture_quality: CaptureQuality?
    let source: String?

    // Form fundamentals v1 (DEC-057) — the after_form_analyzed footer fields written onto the record.
    // key_frames: the KEY POSITIONS stills actually exported (fetched via GET /shots/{id}/frame/{key}).
    // events: located event times (E2/E3/E4/E7 …) so a thumbnail can show its honest timestamp.
    let key_frames: [String]?
    let events: [String: FlexNum]?
    let timing_checkpoints: [String: TimingCheckpoint]?
    let measured_positions: [String: MeasuredPosition]?
    let swing_timing: SwingTiming?
    let coaching_cues: CoachingCues?
    let focus: FormFocus?
    let footer: FormFooter?

    enum CodingKeys: String, CodingKey {
        case shot_id, metrics, insights, form_version, view, status, fps
        case key_frames, events, timing_checkpoints, measured_positions
        case swing_timing, coaching_cues, focus, footer
        case capture_quality, source
    }

    // Lenient decode: decode each field independently with `try?` so one malformed/unexpected form field
    // can never break the whole record (a ball shot carries none of these; a form shot may carry a
    // subset while the pose backend evolves).
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        shot_id = (try? c?.decodeIfPresent(String.self, forKey: .shot_id)) ?? nil
        metrics = (try? c?.decodeIfPresent([String: Metric].self, forKey: .metrics)) ?? nil
        insights = (try? c?.decodeIfPresent(ShotInsights.self, forKey: .insights)) ?? nil
        form_version = (try? c?.decodeIfPresent(String.self, forKey: .form_version)) ?? nil
        view = (try? c?.decodeIfPresent(String.self, forKey: .view)) ?? nil
        status = (try? c?.decodeIfPresent(String.self, forKey: .status)) ?? nil
        fps = (try? c?.decodeIfPresent(Double.self, forKey: .fps)) ?? nil
        key_frames = (try? c?.decodeIfPresent([String].self, forKey: .key_frames)) ?? nil
        events = (try? c?.decodeIfPresent([String: FlexNum].self, forKey: .events)) ?? nil
        timing_checkpoints = (try? c?.decodeIfPresent([String: TimingCheckpoint].self, forKey: .timing_checkpoints)) ?? nil
        measured_positions = (try? c?.decodeIfPresent([String: MeasuredPosition].self, forKey: .measured_positions)) ?? nil
        swing_timing = (try? c?.decodeIfPresent(SwingTiming.self, forKey: .swing_timing)) ?? nil
        coaching_cues = (try? c?.decodeIfPresent(CoachingCues.self, forKey: .coaching_cues)) ?? nil
        focus = (try? c?.decodeIfPresent(FormFocus.self, forKey: .focus)) ?? nil
        footer = (try? c?.decodeIfPresent(FormFooter.self, forKey: .footer)) ?? nil
        capture_quality = (try? c?.decodeIfPresent(CaptureQuality.self, forKey: .capture_quality)) ?? nil
        source = (try? c?.decodeIfPresent(String.self, forKey: .source)) ?? nil
    }
}

/// Capture-quality assessment written onto the shot record (GUARDRAILS 3.7 B). `far_lane` is "limited"
/// when the downlane depth couldn't be tracked reliably from this camera spot; `reason` is honest text.
struct CaptureQuality: Codable, Equatable {
    let far_lane: String?
    let reason: String?
}

// MARK: - Form fundamentals v1 contract (DEC-057, after_form_analyzed footer / shot record)

/// A JSON number that tolerates null (and int/float). Form phase splits & event times arrive as a number
/// or null; this keeps a null from breaking the surrounding object and never fabricates a value.
struct FlexNum: Codable, Equatable {
    let value: Double?
    init(value: Double?) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : (try? c.decode(Double.self))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// One timing checkpoint (T1 pushaway · T2 ball-start step · T3 backswing apex · T4 leverage window).
/// `verdict` is early/on_time/late or nil; `status` ok|unavailable. `offset` is the measured amount in
/// `unit`; `bar_pos` is the normalized 0…1 marker on the early→late scale. `detail`/`note` are honest text.
struct TimingCheckpoint: Codable, Equatable {
    let id: String?
    let label: String?
    let phase: String?
    let unit: String?
    let offset: Double?
    let verdict: String?
    let status: String?
    let bar_pos: Double?
    let detail: String?
    let note: String?
    let provisional: Bool?
}

/// One measured position (M1 foul line · M2 spine tilt · M3 balance arm · M4 shoulders · M5 follow-through
/// · M6 finish hold · M7 pendulum). `display` is the backend's honest display string (e.g. "22° · steady",
/// "Up to ear", "—"); `status` is ok|best_effort|unavailable with `note` carrying the reason/target.
struct MeasuredPosition: Codable, Equatable {
    let id: String?
    let metric: String?
    let value: Double?
    let unit: String?
    let status: String?
    let note: String?
    let display: String?
    let view_required: String?
}

/// Swing-timing comparison (§0.4): this delivery's phase splits vs the bowler's Profile baseline, per phase.
/// `building == true` → no baseline set, only this delivery, with `prompt`. Phase dicts are keyed by the
/// phase name (pushaway_time/backswing_time/downswing_time/release_time) plus "total".
struct SwingTiming: Codable, Equatable {
    let phases: [String]?
    let phase_labels: [String: String]?
    let this_delivery: [String: FlexNum]?
    let baseline: [String: FlexNum]?
    let diff: [String: FlexNum]?
    let source: String?
    let building: Bool?
    let prompt: String?
}

/// §0.3 hand/wrist coaching cues — text only, never a measured result.
struct CoachingCues: Codable, Equatable {
    let note: String?
    let cues: [String]?
}

/// The prioritized form focus insight (shown as the session-focus card when a rule fires; nil until the
/// bowler's baselines are established). `comparison_text` is the "N of your last 5" honest comparison.
struct FormFocus: Codable, Equatable {
    let cue: String?
    let metric: String?
    let comparison_text: String?
    let rule_id: String?
    let drill: FormDrill?
}

struct FormDrill: Codable, Equatable {
    let id: String?
    let name: String?
    let how: String?
}

/// The form-card footer: analyzed seconds + the three engine versions (form / rules / fundamentals).
struct FormFooter: Codable, Equatable {
    let analyzed_s: Double?
    let form_version: String?
    let rules_version: Double?
    let fundamentals_version: String?
}

/// The bowler's swing-timing baseline, persisted on the profile (PUT /me/profile `form_baseline`).
/// `mode` is "entered" (the four phase seconds the bowler typed) or "average" ("use my average"); phase
/// values are present only for an entered baseline.
struct FormBaseline: Codable, Equatable {
    var mode: String? = nil
    var pushaway_time: Double? = nil
    var backswing_time: Double? = nil
    var downswing_time: Double? = nil
    var release_time: Double? = nil
    var total: Double? = nil
}

/// Analyzed-shot insights (record.insights). `suggested_target` is the server-computed target line for
/// the NEXT shot (null fields where the thrown intent didn't set that board); `recommendations` carries
/// the actionable "Apply this move" rec. Everything optional — absent fields stay absent.
struct ShotInsights: Codable, Equatable {
    let recommendations: [Recommendation]?
    let suggested_target: SuggestedTarget?
    // 3.7 next-shot state machine (GUARDRAILS 3.7 C.7): the app renders the Next Shot card from `state`.
    // One of: move | low_confidence_move | strike_repeat | execution_miss | pins_unknown | no_reliable_data.
    // `confidence` is the qualitative level ("low"|"medium"|"high"); `note` is the honest one-line reason.
    let state: String?
    let confidence: String?
    let note: String?
}

struct Recommendation: Codable, Equatable {
    let type: String?
    let direction: String?       // "left" | "right"
    let move_feet: Double?
    let move_target: Double?      // whole boards (backend sends a number, not a string)
    let reason: String?           // WHY — the evidence for the move
    let expected: String?         // EXPECTED EFFECT — what the move should achieve (MVP-06; may be absent)
    let confidence: String?       // qualitative level: "low" | "medium" | "high" (NOT numeric)
}

/// The next-shot target line computed server-side from the thrown intent. Null board fields mean the
/// intent didn't set that board — leave those unchanged when applying. Do NOT recompute boards in Swift.
struct SuggestedTarget: Codable, Equatable {
    let feet_board: Double?
    let arrows_board: Double?
    let breakpoint_board: Double?
    let direction: String?
    let move_feet: Double?
    let move_target: Double?

    /// True only when there is at least one board value to apply.
    var hasBoard: Bool { feet_board != nil || arrows_board != nil || breakpoint_board != nil }
}

struct Metric: Codable {
    let metric: String?
    let value: Double?
    let unit: String?
    let status: String?
    let note: String?
    let confidence: Double?
    let uncertainty: Double?    // ± band for a best-effort/estimate value (e.g. rev rate ±16); nil when unknown
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
    // Richer session-end payload (POST /sessions/{id}/end)
    let tier_event: TierEvent?
    let personal_best: Bool?
    let unlocked: [String]?
    let notifications: [AppNotification]?
}

struct ScoreBrief: Codable {
    let eligible: Bool?
    let score: Double?
    let tier: String?
}

struct TierEvent: Codable, Equatable {
    let kind: String?        // promotion | demotion
    let from_tier: String?
    let to_tier: String?
    let first_time: Bool?
    let score: Double?
}

// MARK: - Live session shot rows (GET /sessions/{id}/shots)

struct SessionShotRow: Codable, Identifiable, Equatable {
    let id: String
    let state: String?           // pending | analyzed | failed
    let created_at: Double?      // epoch seconds — decoded leniently from a Double OR an ISO-8601 string
    let classification: String?  // e.g. pocket / light / high (from insights)
    let source: String?          // live | upload
    let metrics: ShotRowMetrics?

    enum CodingKeys: String, CodingKey { case id, state, created_at, classification, source, metrics }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        state = try? c.decodeIfPresent(String.self, forKey: .state)
        created_at = APIDate.epoch(c, .created_at)
        classification = try? c.decodeIfPresent(String.self, forKey: .classification)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        metrics = try? c.decodeIfPresent(ShotRowMetrics.self, forKey: .metrics)
    }
}

/// Decodes a timestamp that the API may send as epoch seconds (Double) OR an ISO-8601 string, so a
/// backend that hasn't normalized a column to epoch never breaks the client. Returns epoch seconds.
enum APIDate {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoNoFrac = ISO8601DateFormatter()

    static func epoch<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        guard let s = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        if let date = iso.date(from: s) ?? isoNoFrac.date(from: s) { return date.timeIntervalSince1970 }
        return Double(s)
    }
}

struct ShotRowMetrics: Codable, Equatable {
    let ball_speed: Double?
    let rev_rate: Double?
    let entry_board: Double?
    let entry_angle: Double?
    let arrows_board: Double?
}

// MARK: - Per-metric detail (GET /me/stats/metric/{metric})

struct MetricDetailResponse: Codable {
    let metric: String?
    let n: Int?
    let coverage: Double?          // measured / total (0…1)
    let status: String?            // ok | building
    let avg: Double?
    let spread: Double?            // robust spread (1.4826·MAD)
    let range: [Double]?           // [lo, hi]
    let trend: [MetricTrendPoint]?
    let by_ball: [MetricGroupStat]?
    let by_pattern: [MetricGroupStat]?
    let small_sample: Bool?
}

struct MetricTrendPoint: Codable, Identifiable {
    let session_id: String?
    let n: Int?
    let mean: Double?
    var id: String { session_id ?? UUID().uuidString }
}

struct MetricGroupStat: Codable, Identifiable {
    let key: String?
    let n: Int?
    let mean: Double?
    var id: String { key ?? UUID().uuidString }
}

// MARK: - Equipment rollup (GET /me/stats/equipment)

struct EquipmentStats: Codable {
    let by_ball: [EquipGroup]?
    let by_pattern: [EquipGroup]?
}

struct EquipGroup: Codable, Identifiable {
    let id: String?
    let name: String?
    let n: Int?
    let speed: Double?
    let rev: Double?
    let pocket_pct: Double?
    var identity: String { id ?? name ?? UUID().uuidString }
}

// MARK: - Score-parts breakdown (GET /me/score/breakdown)

struct ScoreBreakdown: Codable {
    let performance: PerfPart?
    let accuracy: AccPart?
    let consistency: ConsPart?
    let power: PowerPart?

    struct PerfPart: Codable { let value: Double?; let pocket_pct: Double?; let angle_pct: Double? }
    struct AccPart: Codable {
        let value: Double?; let avg_arrow_miss: Double?; let avg_bp_miss: Double?
        let n_with_target: Int?; let n_total: Int?
    }
    struct ConsPart: Codable { let value: Double?; let spreads: [String: Double]? }
    struct PowerPart: Codable { let value: Double?; let entry_speed: Double?; let rev_rate: Double?; let entry_angle: Double? }
}

// MARK: - Session summary / aggregates (GET /sessions/{id}/summary)

struct SessionSummary: Codable {
    let session_id: String?
    let n_shots: Int?
    let metrics: [String: MetricAggregate]?
    let consistency: SessionConsistency?
    let typical: SessionTypical?
    let early_vs_late: [String: EarlyLate]?
    let focus: SessionFocus?

    func mean(_ key: String) -> Double? { metrics?[key]?.mean }
}

struct SessionTypical: Codable {
    let status: String?            // ok | building
    let n_sessions: Int?
    let need: Int?
    let metrics: [String: Double]?
}

struct EarlyLate: Codable {
    let early: Double?
    let late: Double?
    let delta: Double?
    let n_early: Int?
    let n_late: Int?
}

struct SessionFocus: Codable {
    let status: String?            // ok | building
    let focus: String?             // the templated focus title, or "Keep repeating" / "Mixed results"
    let detail: String?            // the shot's own recommendation copy (no invented text)
    let expected: String?
    let state: String?
}

struct MetricAggregate: Codable {
    let n: Int?
    let mean: Double?
    let sd: Double?
    let min: Double?
    let max: Double?
}

struct SessionConsistency: Codable {
    let repeatability_score: Double?
}

// MARK: - Standalone upload analyses (GET /me/uploads, DEC-055)

struct UploadRow: Codable, Identifiable, Equatable {
    let id: String
    let state: String?            // pending | analyzed | failed
    let created_at: Double?
    let capture_mode: String?     // shot | form (drives the SHOT/FORM badge + result routing)
    let classification: String?
    let source: String?           // always "upload"
    let metrics: ShotRowMetrics?
}

// MARK: - Home Recent activity (GET /me/activity, DEC-055)
//
// Server-scoped to completed practice sessions, achievement unlocks and tier (rank) changes.

struct ActivityItem: Codable, Identifiable, Equatable {
    let id: String
    let kind: String?             // achievement_unlocked | tier_promotion | tier_demotion | session_completed
    let ref_id: String?
    let created_at: Double?
    let payload: ActivityPayload?
}

struct ActivityPayload: Codable, Equatable {
    let name: String?             // achievement name
    let description: String?
    let to_tier: String?          // tier change target
    let from_tier: String?
    let score: Double?
}

// MARK: - Stats (GET /me/stats?view=throw|form)

struct StatsResponse: Codable, Equatable {
    let view: String?
    let empty: Bool?
    let n_shots: Int?
    let averages: [String: MetricAverage]?
    let metric_coverage: [String: MetricCoverage]?
    let top_failure_reasons: [FailureReason]?
    let note: String?
}

struct MetricAverage: Codable, Equatable {
    let mean: Double?
    let n: Int?
}

struct MetricCoverage: Codable, Equatable {
    let measured: Int?
    let total: Int?
    let pct: Double?
}

struct FailureReason: Codable, Equatable, Identifiable {
    let metric: String?
    let reason: String?
    let count: Int?
    var id: String { (metric ?? "") + "|" + (reason ?? "") }
}

// MARK: - Achievements (GET /me/achievements, /{id}, PUT /pins)

struct AchievementsResponse: Codable, Equatable {
    let unlocked_count: Int?
    let categories: [String: [Achievement]]?
    let pins: [AchievementPin]?
}

struct Achievement: Codable, Equatable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let category: String?
    let status: String?            // active | coming_later
    let inactive_reason: String?
    let progress_status: String?   // locked | in_progress | not_trackable | unlocked
    let current_value: Flex?
    let target_value: Flex?
    let best_value: Flex?
    let qualifying_count: Int?
    let sample_count: Int?
    let unavailable_reason: String?
    let unlocked: Bool?
}

struct AchievementPin: Codable, Equatable, Identifiable {
    let achievement_id: String
    let kind: String?              // showcase | pursuit
    let position: Int?
    var id: String { achievement_id }
}

struct PinsResponse: Codable, Equatable {
    let pins: [AchievementPin]?
}

struct AchievementDetail: Codable, Equatable {
    let id: String
    let name: String?
    let description: String?
    let category: String?
    let status: String?
    let inactive_reason: String?
    let progress: AchievementProgress?
    let evidence_shot_ids: [String]?
    let unlocked: Bool?
    let unlocked_at: Double?
    let rule_version: Int?
}

struct AchievementProgress: Codable, Equatable {
    let status: String?
    let current_value: Flex?
    let target_value: Flex?
    let best_value: Flex?
    let qualifying_count: Int?
    let sample_count: Int?
    let unavailable_reason: String?
}

// MARK: - Notifications / celebrations (GET /me/notifications)

struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let kind: String               // achievement_popup | tier_celebration | tier_banner
    let ref_id: String?
    let priority: Int?
    let payload: NotifPayload?
    let created_at: Double?
    let delivered_at: Double?
    let dismissed_at: Double?
}

/// Union of the two notification payload shapes (achievement_popup vs tier_*). Every field optional.
struct NotifPayload: Codable, Equatable {
    // achievement_popup
    let achievement_id: String?
    let name: String?
    let description: String?
    let category: String?
    let value: Flex?
    let target: Flex?
    // tier_celebration / tier_banner
    let kind: String?
    let from_tier: String?
    let to_tier: String?
    let first_time: Bool?
    let score: Double?
    let next_tier: String?
    let points: Double?
}

// MARK: - Lenient number-or-string scalar
//
// Several achievement fields (current_value / target_value) are numeric for most rules but a tier
// *name* string for first_tier rules. Flex decodes either without breaking and exposes both views:
// `.double` for progress math, `.display` for an honest label. Never fabricates a value.
struct Flex: Codable, Equatable {
    let double: Double?
    let display: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            double = nil; display = nil
        } else if let d = try? c.decode(Double.self) {
            double = d
            display = (d.rounded() == d) ? String(Int(d)) : String(format: "%g", d)
        } else if let s = try? c.decode(String.self) {
            display = s; double = Double(s)
        } else if let b = try? c.decode(Bool.self) {
            display = String(b); double = nil
        } else {
            double = nil; display = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let double { try c.encode(double) } else { try c.encode(display) }
    }
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
    var form_baseline: FormBaseline?
    var has_avatar: Bool?             // profile photo set (served by GET /me/avatar)
    var avatar_updated_at: String?    // cache-buster for the avatar image
}

/// Result of PUT/DELETE /me/avatar (handoff G).
struct AvatarStatus: Codable, Equatable {
    let has_avatar: Bool
    let avatar_updated_at: String?
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
    let rg: Double?
    let diff: Double?
    let factory_finish: String?
    let ls_hook: FlexString?
    let ls_length: FlexString?
    let ls_backend: FlexString?
    let image_url: String?

    /// "2.48 / 0.051" when both are present, else "—" (honest; the catalog row lacks the spec).
    var rgDiff: String? {
        guard rg != nil || diff != nil else { return nil }
        let r = rg.map { String(format: "%.2f", $0) } ?? "—"
        let d = diff.map { String(format: "%.3f", $0) } ?? "—"
        return "\(r) / \(d)"
    }
}

// MARK: - Arsenal (GET/POST /me/arsenal, PATCH /me/arsenal/{id})

/// A ball in the user's arsenal. `name` is the display name (catalog "Manufacturer Model", else the
/// custom nickname). Exactly one row has `is_current == true` (server-enforced). `ball_configuration_id`
/// + `id` are sent with every shot so the analyzer knows which ball was thrown.
struct ArsenalBall: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let nickname: String?
    let ball_model_id: String?
    let manufacturer: String?
    let model_name: String?
    let image_url: String?
    let weight_lb: Double?
    let color_desc: String?
    let is_current: Bool?
    let retired: Bool?
    let ball_configuration_id: String?
    let layout_system: String?
    let layout: String?
    let surface: String?

    var displayName: String { name ?? nickname ?? model_name ?? "Ball" }

    // Decode leniently: weight can arrive as a number or string; booleans/strings tolerate nulls.
    enum CodingKeys: String, CodingKey {
        case id, name, nickname, ball_model_id, manufacturer, model_name, image_url,
             weight_lb, color_desc, is_current, retired, ball_configuration_id,
             layout_system, layout, surface
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        nickname = try? c.decodeIfPresent(String.self, forKey: .nickname)
        ball_model_id = try? c.decodeIfPresent(String.self, forKey: .ball_model_id)
        manufacturer = try? c.decodeIfPresent(String.self, forKey: .manufacturer)
        model_name = try? c.decodeIfPresent(String.self, forKey: .model_name)
        image_url = try? c.decodeIfPresent(String.self, forKey: .image_url)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .weight_lb) { weight_lb = d }
        else if let s = try? c.decodeIfPresent(String.self, forKey: .weight_lb) { weight_lb = Double(s) }
        else { weight_lb = nil }
        color_desc = try? c.decodeIfPresent(String.self, forKey: .color_desc)
        is_current = (try? c.decodeIfPresent(Bool.self, forKey: .is_current)) ?? false
        retired = (try? c.decodeIfPresent(Bool.self, forKey: .retired)) ?? false
        ball_configuration_id = try? c.decodeIfPresent(String.self, forKey: .ball_configuration_id)
        layout_system = try? c.decodeIfPresent(String.self, forKey: .layout_system)
        layout = try? c.decodeIfPresent(String.self, forKey: .layout)
        surface = try? c.decodeIfPresent(String.self, forKey: .surface)
    }
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

struct ShotIntent: Equatable {
    var feetBoard: Double?
    var arrowsBoard: Double?
    var breakpointBoard: Double?

    /// True when at least one board target is set (i.e. Accuracy can be scored for the shot).
    var isEmpty: Bool { feetBoard == nil && arrowsBoard == nil && breakpointBoard == nil }
}

struct ShotMetadata {
    var handed: String          // "R" / "L"
    var captureMode: String     // "shot" / "form"
    var source: String          // "live"
    /// The boards ACTUALLY used for this shot (the current session target at capture, including any
    /// chip edits made after an "Apply this move").
    var intent: ShotIntent
    /// The last "Apply this move" proposal snapshot (feet/arrows/breakpoint from the server's
    /// `suggested_target`), or nil if no move was applied. Stored by the server alongside `intent` so a
    /// post-apply edit is visible: `intent` reflects the edit while `suggested` keeps what was proposed.
    var suggested: ShotIntent?
    /// Current ball's `ball_configuration_id` and arsenal row `id` (sent so the analyzer knows the ball).
    var ballConfigurationId: String?
    var userBallId: String?

    /// Builds the exact JSON string the API expects for the `metadata` multipart field.
    /// Intent values are emitted explicitly as `null` when absent (matches the contract); the ball ids
    /// and the `suggested` object are included only when known.
    private static func boardDict(_ i: ShotIntent) -> [String: Any] {
        [
            "feet_board": i.feetBoard as Any? ?? NSNull(),
            "arrows_board": i.arrowsBoard as Any? ?? NSNull(),
            "breakpoint_board": i.breakpointBoard as Any? ?? NSNull(),
        ]
    }

    func jsonString() -> String {
        var dict: [String: Any] = [
            "handed": handed,
            "capture_mode": captureMode,
            "source": source,
            "intent": Self.boardDict(intent),
        ]
        if let suggested { dict["suggested"] = Self.boardDict(suggested) }
        if let ballConfigurationId { dict["ball_configuration_id"] = ballConfigurationId }
        if let userBallId { dict["user_ball_id"] = userBallId }
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

// MARK: - Form (FORM_P1) display

/// Ordering, labels, and honest value formatting for the provisional FORM_P1 metrics (form_version
/// 0.0.0). These are deliberately separate from the ball `MetricDisplay`: form metrics have their own
/// grouping (swing phases first) and their own formatting rules (seconds/ratios to 2 dp, counts as
/// integers). Nothing here fabricates a value — a null value stays "not measured".
enum FormMetricDisplay {
    /// The canonical FORM_P1 keys the backend emits.
    static let p1Keys: Set<String> = [
        "pushaway_time", "backswing_time", "downswing_time", "swing_time",
        "approach_time", "step_count", "ball_start_step", "rhythm_ratio",
        "finish_hold", "backswing_height_rel", "drift_boards",
    ]

    /// Preferred display order: swing phases grouped first, then the rest.
    static let preferredOrder: [String] = [
        "pushaway_time", "backswing_time", "downswing_time", "swing_time",
        "approach_time", "step_count", "ball_start_step", "rhythm_ratio",
        "finish_hold", "backswing_height_rel", "drift_boards",
    ]

    /// True if any FORM_P1 key is present — the fallback form-result signal when the capture mode and
    /// `form_version` are both unknown.
    static func looksLikeForm(_ metrics: [String: Metric]?) -> Bool {
        guard let metrics else { return false }
        return metrics.keys.contains { p1Keys.contains($0) }
    }

    /// (name, metric) pairs in the grouped order above; any unlisted key is appended alphabetically.
    static func ordered(_ metrics: [String: Metric]) -> [(String, Metric)] {
        let known = preferredOrder.compactMap { name in metrics[name].map { (name, $0) } }
        let rest = metrics.keys
            .filter { !preferredOrder.contains($0) }
            .sorted()
            .compactMap { name in metrics[name].map { (name, $0) } }
        return known + rest
    }

    /// Human labels tuned for the swing timeline (fallback: generic humanize).
    static func label(_ name: String) -> String {
        switch name {
        case "pushaway_time": return "Pushaway"
        case "backswing_time": return "Backswing"
        case "downswing_time": return "Downswing"
        case "swing_time": return "Total swing"
        case "approach_time": return "Approach"
        case "step_count": return "Steps"
        case "ball_start_step": return "Ball-start step"
        case "rhythm_ratio": return "Rhythm ratio"
        case "finish_hold": return "Finish hold"
        case "backswing_height_rel": return "Backswing height"
        case "drift_boards": return "Drift"
        default: return MetricDisplay.humanize(name)
        }
    }

    /// Honest formatting of a form value. Returns nil when there is no value (shown as "—").
    /// Seconds & ratios → 2 dp; counts/indices → integer; boards → 1 dp.
    static func formattedValue(key: String, _ m: Metric) -> String? {
        guard let v = m.value else { return nil }
        switch key {
        case "step_count", "ball_start_step":
            return String(Int(v.rounded()))
        case "drift_boards":
            return String(format: "%.1f", v)
        default:   // *_time (s) and *_ratio / *_rel (ratio)
            return String(format: "%.2f", v)
        }
    }

    /// Unit text to show after the value. Counts/indices/ratios read fine without a unit word, so those
    /// are suppressed; seconds and boards keep their unit.
    static func unitText(key: String, _ m: Metric) -> String? {
        guard let unit = m.unit, !unit.isEmpty else { return nil }
        switch unit.lowercased() {
        case "count", "index", "ratio": return nil
        default: return unit
        }
    }
}

/// The three honest states a provisional form metric can be in. Unlike the ball `MetricStatus`, a
/// "low_confidence" metric is an *estimate* (we still show the number with a tag), not hidden.
enum FormMetricState {
    case ok, estimate, unavailable

    /// Delegates to the single `MetricStatus` mapping (Theme.swift) so ball and form can never disagree
    /// on what a status string means (GUARDRAILS 3.7 F — one mapping everywhere): measured→ok,
    /// bestEffort→estimate (best_effort / low_confidence / calibrated_estimate), unavailable→unavailable.
    init(_ raw: String?) {
        switch MetricStatus(raw) {
        case .measured: self = .ok
        case .bestEffort: self = .estimate
        case .unavailable: self = .unavailable
        }
    }

    /// Small tag shown beside estimates; nil for ok/unavailable (unavailable is handled separately).
    var tag: String? {
        switch self {
        case .ok: return nil
        case .estimate: return "ESTIMATE"
        case .unavailable: return nil
        }
    }
}
