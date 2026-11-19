import AppKit
import CoreGraphics
import Foundation
import IOKit

/// What macOS says about one online display, for matching it to an IORegistry service.
struct DisplayFacts: Equatable, Sendable {
    var displayID: CGDirectDisplayID
    var vendorID: UInt32
    var productID: UInt32
    var serialNumber: UInt32
    var name: String
    var isBuiltIn: Bool
    /// The framebuffer's IORegistry path, from CoreDisplay.
    var location: String?
    var weekOfManufacture: Int?
    var yearOfManufacture: Int?
    /// Physical size in millimetres.
    var imageSize: (width: Int, height: Int)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayID == rhs.displayID && lhs.vendorID == rhs.vendorID && lhs.productID == rhs.productID
            && lhs.serialNumber == rhs.serialNumber && lhs.name == rhs.name && lhs.location == rhs.location
            && lhs.imageSize?.width == rhs.imageSize?.width && lhs.imageSize?.height == rhs.imageSize?.height
    }
}

/// One framebuffer and the external AV service under it, as the IORegistry lists them.
struct DDCServiceCandidate: Equatable, Sendable {
    /// Position in registry order, which tells candidates apart.
    var index: Int
    var registryID: UInt64
    var location: String
    var edidUUID: String?
    var productName: String?
    var serialNumber: UInt32?
    var vendorID: UInt32?
    var productID: UInt32?
    /// The link as the AV service names it, for example "DP" or "HDMI".
    var transport: String?
}

/// Pairs displays with DDC services the way MonitorControl's `Arm64DDC.swift` does
/// (`:42-70, 128-164`): score every pair on the facts both sides report, then assign
/// greedily from the best score down so no service is ever used for two displays.
enum DDCServiceMatcher {
    struct Match: Equatable, Sendable {
        let candidate: DDCServiceCandidate
        let score: Int
        /// Which facts agreed, in words, for `--probe-displays` and Connection details.
        let reasons: [String]
    }

    /// The registry path is unique to one framebuffer, so it outweighs everything else.
    static let locationWeight = 10

    static func score(_ display: DisplayFacts, _ candidate: DDCServiceCandidate) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []
        func agree(_ reason: String, weight: Int = 1) { score += weight; reasons.append(reason) }

        if let location = display.location, location == candidate.location { agree("framebuffer location", weight: locationWeight) }
        // The EDID UUID packs EDID bytes as hex: vendor at 0, product (little-endian) at 4,
        // manufacture week and year at 19, image size in centimetres at 30.
        if let uuid = candidate.edidUUID?.uppercased() {
            func field(at offset: Int) -> String? {
                guard uuid.count >= offset + 4 else { return nil }
                let start = uuid.index(uuid.startIndex, offsetBy: offset)
                return String(uuid[start..<uuid.index(start, offsetBy: 4)])
            }
            let vendor = String(format: "%04X", display.vendorID & 0xFFFF)
            let product = String(format: "%02X%02X", display.productID & 0xFF, (display.productID >> 8) & 0xFF)
            if vendor != "0000", field(at: 0) == vendor { agree("EDID vendor") }
            if product != "0000", field(at: 4) == product { agree("EDID product") }
            if let week = display.weekOfManufacture, let year = display.yearOfManufacture, year > 1990 {
                let date = String(format: "%02X%02X", min(255, week), min(255, year - 1990))
                if date != "0000", field(at: 19) == date { agree("EDID manufacture date") }
            }
            if let size = display.imageSize {
                let centimetres = String(format: "%02X%02X", min(255, (size.width + 5) / 10), min(255, (size.height + 5) / 10))
                if centimetres != "0000", field(at: 30) == centimetres { agree("EDID image size") }
            }
        }
        if let vendor = candidate.vendorID, vendor != 0, vendor == display.vendorID { agree("vendor") }
        if let product = candidate.productID, product != 0, product == display.productID { agree("product") }
        if let serial = candidate.serialNumber, serial != 0, serial == display.serialNumber { agree("serial number") }
        if let name = candidate.productName, !name.isEmpty, name.caseInsensitiveCompare(display.name) == .orderedSame { agree("product name") }
        return (score, reasons)
    }

    /// Best pairs first. A display or service already taken is skipped, and a pair with no
    /// agreeing facts never matches.
    static func assign(_ displays: [DisplayFacts], to candidates: [DDCServiceCandidate]) -> [CGDirectDisplayID: Match] {
        var pairs: [(display: CGDirectDisplayID, match: Match)] = []
        for display in displays where !display.isBuiltIn {
            for candidate in candidates {
                let (score, reasons) = score(display, candidate)
                if score > 0 { pairs.append((display.displayID, Match(candidate: candidate, score: score, reasons: reasons))) }
            }
        }
        pairs.sort { ($0.match.score, -$0.match.candidate.index) > ($1.match.score, -$1.match.candidate.index) }
        var result: [CGDirectDisplayID: Match] = [:]
        var usedServices = Set<UInt64>()
        for pair in pairs where result[pair.display] == nil && !usedServices.contains(pair.match.candidate.registryID) {
            result[pair.display] = pair.match
            usedServices.insert(pair.match.candidate.registryID)
        }
        return result
    }
}

/// Reads displays and AV services from macOS. Read-only: nothing here sends to a display.
enum DisplayRegistry {
    typealias InfoDictionary = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    /// CoreDisplay's per-display dictionary, which carries the framebuffer path and EDID
    /// dates. Private; if it's gone, matching uses the public facts alone.
    private static let infoDictionary: InfoDictionary? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW),
              let symbol = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(symbol, to: InfoDictionary.self)
    }()

    /// The built-in display goes by the Mac it's in ("MacBook Air"), not macOS's "Built-in
    /// Retina Display": the device tree's product name, without its size and year.
    private static let macName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return "This Mac" }
        defer { IOObjectRelease(entry) }
        let bytes = property(entry, "product-name") as? Data
        return macName(productName: bytes.map { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
    }()

    static func macName(productName: String?) -> String {
        let full = productName ?? ""
        let family = (full.firstIndex(of: "(").map { String(full[..<$0]) } ?? full).trimmingCharacters(in: .whitespaces)
        return family.isEmpty ? "This Mac" : family
    }

    /// Online displays, leaving out those that mirror another.
    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }

    @MainActor static func facts(for displayID: CGDirectDisplayID) -> DisplayFacts {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
        let builtIn = CGDisplayIsBuiltin(displayID) != 0
        var facts = DisplayFacts(
            displayID: displayID,
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            name: builtIn ? macName : screen?.localizedName ?? "External display",
            isBuiltIn: builtIn
        )
        let size = CGDisplayScreenSize(displayID)
        if size.width > 0, size.height > 0 { facts.imageSize = (Int(size.width.rounded()), Int(size.height.rounded())) }
        if let info = infoDictionary?(displayID)?.takeRetainedValue() as NSDictionary? {
            facts.location = info["IODisplayLocation"] as? String
            facts.weekOfManufacture = (info["DisplayWeekManufacture"] as? NSNumber)?.intValue
            facts.yearOfManufacture = (info["DisplayYearManufacture"] as? NSNumber)?.intValue
            if let width = (info["DisplayHorizontalImageSize"] as? NSNumber)?.intValue,
               let height = (info["DisplayVerticalImageSize"] as? NSNumber)?.intValue, width > 0, height > 0 {
                facts.imageSize = (width, height)
            }
        }
        return facts
    }

    /// Every framebuffer with an external AV service under it, in registry order. Each AV
    /// proxy belongs to the framebuffer listed before it.
    static func externalServices() -> [DDCServiceCandidate] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var candidates: [DDCServiceCandidate] = []
        var framebuffer: DDCServiceCandidate?
        var index = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            switch name(of: entry) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                index += 1
                framebuffer = candidate(framebuffer: entry, index: index)
            case "DCPAVServiceProxy":
                guard var current = framebuffer, property(entry, "Location") as? String == "External" else { continue }
                var registryID: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(entry, &registryID)
                current.registryID = registryID
                if let transport = property(entry, "Transport") as? [String: Any] {
                    current.transport = (transport["Downstream"] as? String) ?? (transport["Upstream"] as? String)
                }
                candidates.append(current)
                framebuffer = nil
            default:
                continue
            }
        }
        return candidates
    }

    /// Opens a link to the AV service with this registry ID, or nil if it's gone.
    static func link(registryID: UInt64, profile: DDCTransportProfile = .standard) -> DDCLink? {
        guard let matching = IORegistryEntryIDMatching(registryID) else { return nil }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return DDCLink(registryEntry: entry, registryID: registryID, profile: profile)
    }

    private static func candidate(framebuffer entry: io_registry_entry_t, index: Int) -> DDCServiceCandidate {
        var path = [CChar](repeating: 0, count: 1024)
        IORegistryEntryGetPath(entry, kIOServicePlane, &path)
        let attributes = (property(entry, "DisplayAttributes") as? [String: Any])?["ProductAttributes"] as? [String: Any]
        func number(_ key: String) -> UInt32? { (attributes?[key] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) } }
        return DDCServiceCandidate(
            index: index, registryID: 0,
            location: text(path),
            edidUUID: property(entry, "EDID UUID") as? String,
            productName: attributes?["ProductName"] as? String,
            serialNumber: number("SerialNumber"),
            vendorID: number("LegacyManufacturerID"),
            productID: number("ProductID")
        )
    }

    private static func name(of entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &buffer)
        return text(buffer)
    }

    /// A C string IOKit filled in, up to its terminator.
    private static func text(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
