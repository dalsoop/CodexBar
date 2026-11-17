import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// `cfprefsd` stores every `UserDefaults(suiteName:)` domain in the real account's `~/Library/Preferences`, even
/// when the test runner sets a temporary `HOME` and `CFFIXED_USER_HOME`, and `removePersistentDomain(forName:)`
/// leaves an empty plist behind. Without cleanup every run adds one file per suite to the developer's Mac.
///
/// Inside this test target, this overload is preferred over Foundation's `init?(suiteName: String?)` for every
/// non-optional suite name, so each suite a test creates is recorded and its plist is deleted when the test
/// process exits. Suite names, domains and per-test `removePersistentDomain(forName:)` calls stay unchanged.
extension UserDefaults {
    convenience init?(suiteName: String) {
        TestUserDefaultsSuites.track(suiteName)
        self.init(suiteName: Optional(suiteName))
    }
}

enum TestUserDefaultsSuites {
    /// `cfprefsd` writes a change to disk up to about 9 s after it is made (measured on macOS 27, including
    /// `removePersistentDomain`), and a plist deleted before that write comes back. Exit cleanup therefore keeps
    /// deleting until this long after the last defaults change made by this process.
    private static let flushSettleInterval: TimeInterval = 12
    private static let pollInterval: useconds_t = 250_000

    private static let lock = NSLock()
    private nonisolated(unsafe) static var names: Set<String> = []
    private nonisolated(unsafe) static var lastChange = Date.distantPast

    private static let installExitCleanup: Void = {
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil)
        { _ in
            TestUserDefaultsSuites.noteChange()
        }
        _ = atexit { TestUserDefaultsSuites.removeTrackedPlists() }
    }()

    static func track(_ suiteName: String) {
        _ = self.installExitCleanup
        self.lock.withLock {
            self.names.insert(suiteName)
            self.lastChange = Date()
        }
    }

    private static func noteChange() {
        self.lock.withLock { self.lastChange = Date() }
    }

    private static func removeTrackedPlists() {
        let names = self.lock.withLock { self.names }.filter(self.isTestOwned)
        guard !names.isEmpty, let preferences = self.preferencesDirectory() else { return }
        for name in names {
            CFPreferencesAppSynchronize(name as CFString)
        }
        let plists = names.map { preferences.appendingPathComponent("\($0).plist") }
        let settled = self.lock.withLock { self.lastChange }.addingTimeInterval(self.flushSettleInterval)
        while true {
            for plist in plists {
                try? FileManager.default.removeItem(at: plist)
            }
            guard Date() < settled else { return }
            usleep(self.pollInterval)
        }
    }

    /// `cfprefsd` ignores `HOME` and `CFFIXED_USER_HOME`, so resolve the account's home from the user database.
    private static func preferencesDirectory() -> URL? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    /// Never delete a system or shipped app domain, whatever name a test passes. The default APFS volume is
    /// case-insensitive, so compare lowercased names.
    private static func isTestOwned(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return false }
        let lowercased = name.lowercased()
        if ["codexbar", "com.steipete.codexbar", "net.ranode.codexbar"].contains(lowercased) { return false }
        let reservedPrefixes = ["codexbar.", "com.apple.", "com.steipete.codexbar.", "net.ranode.", "group."]
        return !reservedPrefixes.contains(where: { lowercased.hasPrefix($0) })
    }
}
