import XCTest
@testable import LaneSight

/// DEC-124: the general-feedback request body is built by a pure function so it can be unit-tested without a
/// network call. Category rides in tags[0]; app_phase is always present; optional fields are omitted when nil.
@MainActor
final class FeedbackPayloadTests: XCTestCase {

    func testGeneralFeedbackBodyIncludesCategoryPhaseAndText() throws {
        let diag: [String: Any] = ["device_model": "iPhone16,2", "ios_version": "26.0", "current_screen": "Home"]
        let body = APIClient.generalFeedbackBody(category: "Bug", text: "crashed on upload",
                                                  appPhase: "ff", appVersion: "0.9.0", diagnostics: diag)
        XCTAssertEqual(body["source"] as? String, "general")
        XCTAssertEqual(body["tags"] as? [String], ["Bug"])      // category in tags[0]
        XCTAssertEqual(body["text"] as? String, "crashed on upload")
        XCTAssertEqual(body["app_phase"] as? String, "ff")
        XCTAssertEqual(body["app_version"] as? String, "0.9.0")
        XCTAssertEqual((body["diagnostics"] as? [String: Any])?["current_screen"] as? String, "Home")

        // It must serialize to valid JSON (the client sends it via JSONSerialization).
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testGeneralFeedbackBodyOmitsOptionalFieldsWhenNil() {
        let body = APIClient.generalFeedbackBody(category: "Idea", text: "add dark mode",
                                                 appPhase: "dev", appVersion: nil, diagnostics: nil)
        XCTAssertNil(body["app_version"])
        XCTAssertNil(body["diagnostics"])
        XCTAssertEqual(body["app_phase"] as? String, "dev")      // phase is never omitted
        XCTAssertEqual(body["tags"] as? [String], ["Idea"])
    }

    func testAppPhaseParsing() {
        XCTAssertEqual(AppPhase(rawValue: "ff"), .ff)
        XCTAssertNil(AppPhase(rawValue: "nonsense"))
        // Under the test host (Debug) the build phase resolves to a valid phase, defaulting to dev.
        XCTAssertTrue([.dev, .ff, .beta, .live].contains(AppPhase.current))
        XCTAssertTrue(AppPhase.ff.requiresFFConsent)
        XCTAssertFalse(AppPhase.dev.requiresFFConsent)
    }
}
