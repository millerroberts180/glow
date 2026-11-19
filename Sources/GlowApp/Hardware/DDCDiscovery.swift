import Foundation

/// What one display's DDC/CI discovery tried and what came back, for Connection details,
/// Copy Report and `--probe-displays`.
struct DDCDiscoveryLog: Hashable, Sendable {
    /// One request that decided whether a profile works: the capability report, or a single
    /// Get VCP of brightness.
    struct Attempt: Hashable, Sendable {
        let profile: String
        let request: String
        let answered: Bool
        let detail: String
        /// How long it took; nil for demo displays, which time nothing.
        var milliseconds: Int?
        /// The connection itself refused the request after blocking for seconds
        /// (`DDCProbe.stallLimit`).
        var stalled = false
    }

    /// One Get VCP and the raw values it returned.
    struct Reading: Hashable, Sendable {
        let code: UInt8
        let result: String
        var milliseconds: Int?
    }

    var attempts: [Attempt] = []
    /// The profile that got answers; nil when nothing answered.
    var workingProfile: DDCTransportProfile?
    var capabilityString: String?
    /// Why there's no usable capability report, when there isn't one.
    var capabilityProblem: String?
    var readings: [Reading] = []
    /// Anything else worth knowing, such as profiles skipped this time.
    var note: String?
}

extension DDCDiscoveryLog {
    /// The last request stalled the connection, so discovery went no further.
    var stopped: Bool { attempts.last?.stalled == true }

    /// The working profile and every way it differs from the standard.
    var profileText: String {
        guard let profile = workingProfile else { return "None answered" }
        return profile == .standard ? profile.summary : "\(profile.name): \(profile.summary)"
    }

    var capabilityText: String {
        if let capabilityString { return capabilityString }
        return "None" + (capabilityProblem.map { " (\($0.trimmingCharacters(in: CharacterSet(charactersIn: "."))))" } ?? "")
    }

    static func text(for attempt: Attempt) -> String {
        let after = attempt.milliseconds.map { " after \($0) ms" } ?? ""
        return "\(attempt.profile), \(attempt.request): \(attempt.answered ? "answered" : "no reply")\(after) · \(attempt.detail)"
    }

    static func text(for reading: Reading, evidence: SupportEvidence?) -> String {
        let name = CapabilityCatalog.entry(for: reading.code).map { " \($0.label)" } ?? ""
        let evidence = evidence.map { " · \($0.rawValue)" } ?? ""
        let time = reading.milliseconds.map { " · \($0) ms" } ?? ""
        return "\(CapabilityCatalog.rawCodeLabel(reading.code))\(name): \(reading.result)\(evidence)\(time)"
    }

    /// Plain lines for Copy Report and `--probe-displays`. Each reading names the evidence
    /// its setting ended up with.
    func reportLines(for display: DisplaySnapshot) -> [String] {
        var lines = ["DDC/CI tries:"]
        lines += attempts.map { "- " + Self.text(for: $0) }
        if let note { lines.append("- " + note) }
        lines.append("Working profile: \(profileText)")
        lines.append("Capability string: \(capabilityText)")
        if let capabilityProblem, capabilityString != nil { lines.append("Capability problem: \(capabilityProblem)") }
        lines.append(readings.isEmpty ? "Reads: none" : "Reads:")
        lines += readings.map { "- " + Self.text(for: $0, evidence: display.evidence(forCode: $0.code)) }
        return lines
    }
}

extension DisplaySnapshot {
    /// The evidence of the setting behind a raw VCP code, when Glow shows one.
    func evidence(forCode code: UInt8) -> SupportEvidence? {
        let label = CapabilityCatalog.rawCodeLabel(code)
        return capabilities.first { $0.rawCode == label }?.evidence
    }
}

/// One external display's discovery: the profiles tried, the capability report and every
/// read. It never writes.
struct DDCProbe: Sendable {
    /// The link on the profile that worked; nil when nothing answered.
    let link: (any DDCTransport)?
    let log: DDCDiscoveryLog
    let descriptors: [CapabilityDescriptor]

    var capabilityString: String? { log.capabilityString }
    var problem: String? { log.capabilityProblem }
    var readings: [DDCDiscoveryLog.Reading] { log.readings }

    /// The code every profile is first tried with: nearly every monitor has brightness.
    static let canaryCode: UInt8 = 0x10
    /// Past this, discovery stops reading and says which codes it didn't reach. A display
    /// that blocks for seconds on each read would otherwise hold up every other display.
    static let readingTimeout: Duration = .seconds(20)
    /// A request the connection itself refused after blocking this long, past the longest
    /// retry window on the ladder, means the route doesn't carry DDC/CI: some hubs and
    /// adapters hold each request for seconds and then drop it. Another profile only changes
    /// timing and the source address, which can't help, so discovery stops there instead of
    /// waiting as long again on each one.
    static let stallLimit: Duration = .seconds(3)

    static var openProblem: String {
        if case let .failure(error) = IOAVServiceAPI.shared { return error.localizedDescription }
        return "macOS didn’t open the display’s DDC service."
    }

    /// One link on the standard profile.
    static func run(_ link: any DDCTransport, transport: String) async -> DDCProbe {
        await run(transport: transport, profiles: [.standard]) { _ in link }
    }

    /// Tries each profile in turn until the display answers (ADR 0001, decision 7). The
    /// first asks for the capability report straight away; later ones first send one Get VCP
    /// of brightness, so a silent connection costs one wait per profile, not two. `quick`
    /// starts with that Get VCP too, for a connection that was silent before. A request
    /// that stalls the connection ends the climb (`stallLimit`).
    ///
    /// With a report, Glow reads each setting it lists. Without one, it reads every setting
    /// the catalog knows (`CapabilityDiscovery.unlistedProfile`).
    static func run(
        transport: String, profiles: [DDCTransportProfile], quick: Bool = false, stallLimit: Duration = stallLimit,
        open: (DDCTransportProfile) -> (any DDCTransport)?
    ) async -> DDCProbe {
        var log = DDCDiscoveryLog()
        for (index, profile) in profiles.enumerated() {
            guard let link = open(profile) else {
                log.capabilityProblem = openProblem
                break
            }
            var report: String?
            var known: [UInt8: (ProbeResult, Int)] = [:]
            if index == 0, !quick {
                report = await requestReport(link, profile: profile, stallLimit: stallLimit, log: &log)
                if log.stopped { break }
            }
            if report == nil {
                guard let answer = await canary(link, profile: profile, stallLimit: stallLimit, log: &log) else {
                    if log.stopped { break }
                    continue
                }
                known[canaryCode] = answer
                if index > 0 || quick { report = await requestReport(link, profile: profile, stallLimit: stallLimit, log: &log) }
            }
            log.workingProfile = profile
            let descriptors: [CapabilityDescriptor]
            let deadline = ContinuousClock.now + readingTimeout
            if let report, let parsed = MCCSCapabilities.parse(report) {
                let codes = parsed.codes.map(\.code).filter(CapabilityDiscovery.isProbeable)
                let results = await read(codes, from: link, known: known, deadline: deadline, log: &log)
                // Then, within the same budget, one read of each reported code the catalog
                // doesn't know, for Connection details. Never written (ADR 0002, decision 7).
                let raw = await read(parsed.codes.map(\.code).filter(CapabilityCatalog.readsOnce), from: link, known: [:], deadline: deadline, log: &log)
                descriptors = CapabilityDiscovery.profile(capabilityString: report, transport: transport, read: { results[$0] ?? .noResponse }, readReported: { raw[$0] })
            } else {
                let results = await read(CapabilityDiscovery.unlistedCodes, from: link, known: known, deadline: deadline, log: &log)
                descriptors = CapabilityDiscovery.unlistedProfile(transport: transport) { results[$0] ?? .noResponse }
            }
            return DDCProbe(link: link, log: log, descriptors: descriptors)
        }
        if log.stopped, let attempt = log.attempts.last {
            let seconds = Double(attempt.milliseconds ?? 0) / 1000
            log.note = "Glow stopped there: the connection waited \(seconds.formatted(.number.precision(.fractionLength(1)))) s, then refused the request, which no other profile changes. Some hubs and adapters don’t pass DDC/CI."
        } else if quick, !log.attempts.isEmpty {
            log.note = "Only the standard profile was tried, because this connection didn’t answer earlier. Refresh Displays tries every profile."
        }
        return DDCProbe(link: nil, log: log, descriptors: [])
    }

    /// Refused by the connection itself, not the display, after blocking `limit` or longer.
    private static func stalls(_ error: any Error, since started: ContinuousClock.Instant, limit: Duration) -> Bool {
        switch error as? DDCError {
        case .readFailed?, .sendFailed?: ContinuousClock.now - started >= limit
        default: false
        }
    }

    private static func requestReport(
        _ link: any DDCTransport, profile: DDCTransportProfile, stallLimit: Duration, log: inout DDCDiscoveryLog
    ) async -> String? {
        let started = ContinuousClock.now
        do {
            let raw = try await link.capabilityString()
            let parsed = MCCSCapabilities.parse(raw)
            log.capabilityString = raw
            log.capabilityProblem = parsed == nil ? "the report has no vcp(…) list" : nil
            log.attempts.append(.init(profile: profile.name, request: "capability report", answered: true,
                                      detail: "\(raw.utf8.count) bytes\(parsed == nil ? ", with no vcp(…) list" : "")", milliseconds: elapsed(since: started)))
            return raw
        } catch {
            log.capabilityProblem = error.localizedDescription
            log.attempts.append(.init(profile: profile.name, request: "capability report", answered: false,
                                      detail: error.localizedDescription, milliseconds: elapsed(since: started),
                                      stalled: stalls(error, since: started, limit: stallLimit)))
            return nil
        }
    }

    /// Any reply, even "unsupported", shows the display hears this profile.
    private static func canary(
        _ link: any DDCTransport, profile: DDCTransportProfile, stallLimit: Duration, log: inout DDCDiscoveryLog
    ) async -> (ProbeResult, Int)? {
        let started = ContinuousClock.now
        let request = "Get VCP 0x\(DDCPacket.hex(canaryCode)) (brightness)"
        do {
            let result = try await link.read(code: canaryCode)
            let time = elapsed(since: started)
            let answered = result != .noResponse
            log.attempts.append(.init(profile: profile.name, request: request, answered: answered, detail: describe(result), milliseconds: time))
            return answered ? (result, time) : nil
        } catch {
            log.attempts.append(.init(profile: profile.name, request: request, answered: false,
                                      detail: error.localizedDescription, milliseconds: elapsed(since: started),
                                      stalled: stalls(error, since: started, limit: stallLimit)))
            return nil
        }
    }

    /// One read of each code, reusing any answer the canary already got.
    private static func read(
        _ codes: [UInt8], from link: any DDCTransport, known: [UInt8: (ProbeResult, Int)],
        deadline: ContinuousClock.Instant, log: inout DDCDiscoveryLog
    ) async -> [UInt8: ProbeResult] {
        var results: [UInt8: ProbeResult] = [:]
        for code in codes {
            if case let (result, time)? = known[code] {
                results[code] = result
                log.readings.append(.init(code: code, result: describe(result), milliseconds: time))
                continue
            }
            guard ContinuousClock.now < deadline else {
                log.readings.append(.init(code: code, result: "not read: discovery ran out of time"))
                continue
            }
            let started = ContinuousClock.now
            do {
                let result = try await link.read(code: code)
                results[code] = result
                log.readings.append(.init(code: code, result: describe(result), milliseconds: elapsed(since: started)))
            } catch {
                log.readings.append(.init(code: code, result: "no reply: \(error.localizedDescription)", milliseconds: elapsed(since: started)))
            }
        }
        return results
    }

    static func describe(_ result: ProbeResult) -> String {
        switch result {
        case let .read(current, maximum): "current \(current), maximum \(maximum)"
        case .unsupported: "unsupported (the display refused the code)"
        case .noResponse: "no response"
        }
    }

    private static func elapsed(since started: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - started).milliseconds)
    }
}

/// One display on one route. The same monitor through another port or hub is another
/// connection, and may need another profile.
struct DDCRouteKey: Hashable, Sendable {
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let route: String

    init(_ display: DisplayFacts, registryID: UInt64) {
        vendorID = display.vendorID
        productID = display.productID
        serialNumber = display.serialNumber
        route = display.location ?? "service \(String(registryID, radix: 16))"
    }
}

/// Which profile each connection answered on, and which stayed silent, for this launch.
struct DDCRouteMemory {
    private var working: [DDCRouteKey: DDCTransportProfile] = [:]
    private var silent: Set<DDCRouteKey> = []

    /// The profile that answered last time goes first. A connection no profile reached gets
    /// one quick request until `forgetSilence()`, so wake and reconnect aren't held up.
    func plan(for key: DDCRouteKey, ladder: [DDCTransportProfile]) -> (profiles: [DDCTransportProfile], quick: Bool) {
        if let profile = working[key] { return ([profile] + ladder.filter { $0 != profile }, false) }
        if silent.contains(key) { return (Array(ladder.prefix(1)), true) }
        return (ladder, false)
    }

    mutating func record(_ log: DDCDiscoveryLog, for key: DDCRouteKey) {
        // Nothing was sent (the service wouldn't open), so there's nothing to learn.
        guard !log.attempts.isEmpty else { return }
        if let profile = log.workingProfile {
            working[key] = profile
            silent.remove(key)
        } else {
            working[key] = nil
            silent.insert(key)
        }
    }

    mutating func forgetSilence() { silent.removeAll() }
}
