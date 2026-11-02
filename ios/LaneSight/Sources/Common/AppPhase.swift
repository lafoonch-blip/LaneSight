import Foundation
import UIKit

/// The build's declared test phase (DEC-123). Read from the `LSAppPhase` Info.plist value, which is wired to a
/// per-configuration build setting: Debug → `dev`, Release (the Friends & Family TestFlight build) → `ff`. Later
/// App Store builds set it to `beta` / `live` by changing `LS_APP_PHASE` in project.yml — no code change.
///
/// This is only the build's *request*. The server treats the account cohort as authoritative and forces the
/// owner (Shayne) and every staged test account to `dev` (migration 036), so Shayne's real data and staged test
/// data never mix into F&F / beta / live.
enum AppPhase: String {
    case dev, ff, beta, live

    static let current: AppPhase = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "LSAppPhase") as? String)?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return (raw.flatMap(AppPhase.init(rawValue:))) ?? .dev
    }()

    /// F&F testers must see a one-screen consent before using the app; dev/beta/live don't gate on it here.
    var requiresFFConsent: Bool { self == .ff }
}

/// The LaneSight owner (Shayne). Must match `lanesight_core/owner.py` OWNER_USER_ID and `ops.app_owner`
/// (DEC-098). Used to hide owner-only screens from F&F testers.
enum Owner {
    static let userID = "551bc775-dee4-41bd-a19c-116e8691d053"
}

extension UIDevice {
    /// Hardware model identifier (e.g. "iPhone16,2"), for feedback diagnostics. `model` alone is just "iPhone".
    static var modelIdentifier: String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}
