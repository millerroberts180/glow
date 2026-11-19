import Foundation
import Security

/// What Glow's trial and license keys left on a Mac before they were removed: the days the trial
/// counted, in UserDefaults and in a login Keychain item, and any license key entered. Deleted quietly
/// at each launch; nothing reads them now. The Keychain refuses, without asking, to let one build
/// delete an item another build made, so an item from an older build can stay. It holds only the days
/// the trial counted.
enum LeftoverTrialData {
    static let defaultsKeys = ["TrialRecord", "LicenseKey"]

    static func remove() {
        removeDefaults(from: .standard)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: ReleaseInfo.bundleID,
                                   kSecAttrAccount as String: "trial"]
        _ = SecItemDelete(item as CFDictionary)
    }

    static func removeDefaults(from defaults: UserDefaults) {
        for key in defaultsKeys { defaults.removeObject(forKey: key) }
    }
}
