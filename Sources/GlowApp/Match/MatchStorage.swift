import Foundation

/// A matched display and the reference it follows.
struct MatchPair: Hashable, Codable, Sendable {
    let reference: PersistentDisplayIdentity
    let display: PersistentDisplayIdentity
}

/// One display's match to a reference: the curve its brightness follows, how and when it
/// was made, and how Glow reached each display then. A display whose route has changed
/// since (hardware then, software dimming now) no longer means the same thing by a level,
/// so its match is out of date.
struct MatchCalibration: Hashable, Codable, Sendable {
    let pair: MatchPair
    var curve: BrightnessCurve
    var method: MatchMethod
    var date: Date
    var referenceRoute: ControlRoute
    var displayRoute: ControlRoute

    init(pair: MatchPair, curve: BrightnessCurve, method: MatchMethod, date: Date = .now, referenceRoute: ControlRoute, displayRoute: ControlRoute) {
        self.pair = pair
        self.curve = curve
        self.method = method
        self.date = date
        self.referenceRoute = referenceRoute
        self.displayRoute = displayRoute
    }

    private enum CodingKeys: String, CodingKey { case pair, curve, method, date, referenceRoute, displayRoute }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pair = try c.decode(MatchPair.self, forKey: .pair)
        // Through the curve's own init, so an edited blob can't store a curve that turns back.
        curve = BrightnessCurve(points: try c.decode(BrightnessCurve.self, forKey: .curve).points)
        method = try c.decode(MatchMethod.self, forKey: .method)
        date = try c.decode(Date.self, forKey: .date)
        referenceRoute = try c.decode(ControlRoute.self, forKey: .referenceRoute)
        displayRoute = try c.decode(ControlRoute.self, forKey: .displayRoute)
    }
}

/// Brightness Match as saved inside `GlowSettings`, with a version of its own.
struct BrightnessMatchSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    /// At most one per matched display.
    var calibrations: [MatchCalibration] = []
    /// Moving the reference's own slider moves its matched displays too.
    var moveTogether = false

    init() {}

    private enum CodingKeys: String, CodingKey { case version, calibrations, moveTogether }

    /// Each field on its own, and each calibration on its own, so one that can't be read
    /// (a route from a newer Glow) doesn't take the others with it.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? version
        moveTogether = (try? c.decodeIfPresent(Bool.self, forKey: .moveTogether)) ?? moveTogether
        if var list = try? c.nestedUnkeyedContainer(forKey: .calibrations) {
            while !list.isAtEnd {
                if let calibration = try? list.decode(MatchCalibration.self) {
                    calibrations.removeAll { $0.pair.display == calibration.pair.display }
                    calibrations.append(calibration)
                } else if (try? list.decode(Skipped.self)) == nil {
                    break
                }
            }
        }
    }

    /// Steps over an entry that didn't decode.
    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }

    func calibration(for display: PersistentDisplayIdentity) -> MatchCalibration? {
        calibrations.first { $0.pair.display == display }
    }

    /// Saves one session's matches. Every display in it loses its old match, and none of
    /// the matched displays stays a reference for another, so references never chain.
    mutating func save(_ new: [MatchCalibration]) {
        let involved = Set(new.flatMap { [$0.pair.reference, $0.pair.display] })
        let matched = Set(new.map(\.pair.display))
        calibrations.removeAll { involved.contains($0.pair.display) || matched.contains($0.pair.reference) }
        calibrations += new
    }

    /// Forgets every match that involves one of `displays`.
    mutating func forget(_ displays: Set<PersistentDisplayIdentity>) {
        calibrations.removeAll { displays.contains($0.pair.display) || displays.contains($0.pair.reference) }
    }

    /// Where `display` stands among the connected `displays`.
    func state(of display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> MatchState {
        if let calibration = calibration(for: display.id) {
            let reference = displays.first { $0.id == calibration.pair.reference }
            if display.brightnessRoute != calibration.displayRoute {
                return .outOfDate(calibration, was: calibration.displayRoute, now: display.brightnessRoute)
            }
            if let reference, reference.brightnessRoute != calibration.referenceRoute {
                return .outOfDate(calibration, was: calibration.referenceRoute, now: reference.brightnessRoute)
            }
            return .matched(calibration)
        }
        let followers = calibrations.filter { $0.pair.reference == display.id }
        guard !followers.isEmpty else { return .notMatched }
        if let changed = followers.first(where: { $0.referenceRoute != display.brightnessRoute }) {
            return .outOfDate(changed, was: changed.referenceRoute, now: display.brightnessRoute)
        }
        let connected = displays.filter { candidate in
            followers.contains { $0.pair.display == candidate.id } && candidate.brightnessRoute == calibration(for: candidate.id)?.displayRoute
        }
        return .reference(followers: connected.map(\.name))
    }

    /// Matches whose displays are connected and whose routes still hold: the ones the
    /// brightness keys and a linked slider follow. The reference may be away.
    func active(among displays: [DisplaySnapshot]) -> [MatchCalibration] {
        displays.compactMap { display in
            if case let .matched(calibration) = state(of: display, among: displays) { calibration } else { nil }
        }
    }

    /// The displays with `isAppearanceMatched` set from these matches.
    func annotated(_ displays: [DisplaySnapshot]) -> [DisplaySnapshot] {
        displays.map { display in
            var display = display
            display.isAppearanceMatched = state(of: display, among: displays).isMatched
            return display
        }
    }
}

/// One display's Brightness Match status.
enum MatchState: Equatable, Sendable {
    /// Others follow it; `followers` are the matched displays connected now.
    case reference(followers: [String])
    case matched(MatchCalibration)
    /// Matched once, but one of the two displays is reached another way now.
    case outOfDate(MatchCalibration, was: ControlRoute, now: ControlRoute)
    case notMatched

    var isMatched: Bool {
        switch self {
        case .reference(let followers): !followers.isEmpty
        case .matched: true
        case .outOfDate, .notMatched: false
        }
    }
}
