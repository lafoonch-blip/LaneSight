import XCTest
@testable import LaneSight

/// P0 2026-10-29 contract: the job response's `timings` gained nested fields (client/decode/cv, DEC-092) that a
/// strict [String: Double] decode choked on — failing every post-analysis fetch though the server had analyzed
/// the shot. These tests decode real-shaped server JSON (including the nested timings the old server sent) and
/// assert the app survives it. Guards both directions: the new flat server response AND a regressed nested one.
final class JobContractTests: XCTestCase {

    func testJobResponseDecodesNestedTimingsWithoutThrowing() throws {
        // The exact shape that broke the client: flat numerics mixed with nested objects + a string.
        let json = """
        {"id":"j1","kind":"analyze","state":"done","reason":null,
         "timings":{"analyze":12.35,"window":2.0,
                    "decode":{"passes":9,"seconds":3.5},
                    "cv":{"stabilize_s":14.8},
                    "client":{"trim_s":1.1},
                    "windowed_error":"no sustained burst"},
         "result":null,"failure":null}
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(JobResponse.self, from: json)   // must NOT throw
        XCTAssertEqual(job.state, "done")
        let t = job.timings?.values ?? [:]
        XCTAssertEqual(t["analyze"], 12.35)
        XCTAssertEqual(t["window"], 2.0)
        XCTAssertNil(t["decode"])          // nested objects skipped, not fatal
        XCTAssertNil(t["cv"])
        XCTAssertNil(t["client"])
        XCTAssertNil(t["windowed_error"])  // string skipped
    }

    func testFailedJobDecodesWithFailureSoTheUICanShowIt() throws {
        // P0 2026-10-29 regression: the best-effort job fetch must NEVER swallow a state=failed job. A failed
        // analysis carries the DEC-086 friendly failure — it has to decode (and the app surfaces it + Retry),
        // not drop the user back to Upload with no message. (Even if timings are nested, decode must survive.)
        let json = """
        {"id":"j3","kind":"analyze","state":"failed","reason":"FOUL_LINE_NOT_IN_VIEW",
         "timings":{"analyze":118.0,"cv":{"points_found":0}},
         "result":null,
         "failure":{"code":"FOUL_LINE_NOT_IN_VIEW","stage":"lane","user_title":"We couldn't find the lane",
                    "user_message":"The foul line wasn't in view.","tip":"Set the camera behind the lane."}}
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(JobResponse.self, from: json)
        XCTAssertEqual(job.state, "failed")
        XCTAssertEqual(job.failure?.code, "FOUL_LINE_NOT_IN_VIEW")
        XCTAssertFalse((job.failure?.display ?? "").isEmpty)     // the friendly copy the cover shows
    }

    func testJobResponseDecodesFlatServerResponse() throws {
        // The new server response (Job.public flattens): all-numeric timings + separate timings_detail (ignored).
        let json = """
        {"id":"j2","kind":"analyze","state":"done","reason":null,
         "timings":{"analyze":11.0,"window":1.5,"convert":0},
         "timings_detail":{"decode":{"passes":9}},
         "result":null,"failure":null}
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(JobResponse.self, from: json)
        XCTAssertEqual(job.timings?.values["analyze"], 11.0)
        XCTAssertEqual(job.timings?.values.count, 3)
    }
}
