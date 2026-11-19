import CoreGraphics
import Foundation

/// Brightness for Apple displays and the built-in screen, through the private
/// DisplayServices framework macOS's own brightness keys use. Looked up at run time; if it's
/// missing, those displays fall back to software dimming and say so.
struct NativeBrightness: @unchecked Sendable {
    typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    private let get: Get
    private let set: Set
    private let canChangeBrightness: CanChange

    static let shared: NativeBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness"),
              let can = dlsym(handle, "DisplayServicesCanChangeBrightness") else { return nil }
        return NativeBrightness(
            get: unsafeBitCast(get, to: Get.self),
            set: unsafeBitCast(set, to: Set.self),
            canChangeBrightness: unsafeBitCast(can, to: CanChange.self)
        )
    }()

    func canChange(_ display: CGDirectDisplayID) -> Bool { canChangeBrightness(display) }

    /// 0…1, or nil when the display doesn't answer.
    func brightness(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard get(display, &value) == 0, value.isFinite else { return nil }
        return value
    }

    func setBrightness(_ value: Float, on display: CGDirectDisplayID) -> Bool {
        set(display, min(1, max(0, value))) == 0
    }

    /// Glow shows native brightness as a whole percentage.
    static func percent(_ level: Float) -> Double { (Double(level) * 100).rounded() }
}
