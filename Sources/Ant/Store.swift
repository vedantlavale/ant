import Foundation
import WebKit

// Where everything this browser keeps is kept.
//
// One place, and one rule: a run started for testing never touches the folder
// or the settings of the browser somebody is actually using. Sharing them once
// cost a person their pinned tabs, which is not a mistake worth being able to
// make twice.

enum Store {
    /// A run is a test run if it says so, or if it is being run straight out
    /// of the build folder rather than from an installed app. The second half
    /// is not belt and braces: a development build launched from a terminal
    /// once wrote over somebody's real session, and asking a person to
    /// remember a flag is not a safeguard.
    static var testing: Bool {
        if ProcessInfo.processInfo.environment["ANT_PROBE"] != nil { return true }
        return Bundle.main.executablePath?.contains("/.build/") == true
    }

    /// Which test world a test run lives in. ANT_PROBE=1, or a run from
    /// the build folder, is the test world, "Ant (test)". ANT_PROBE=
    /// <name> is a world of its own, "Ant (<name>)", with settings and
    /// WebKit stores of its own: two sessions testing at once, or a
    /// measurement that needs a browser nobody has installed anything in,
    /// never borrow each other's. Nil for the browser somebody is using.
    static let world: String? = {
        guard testing else { return nil }
        let asked = (ProcessInfo.processInfo.environment["ANT_PROBE"] ?? "").lowercased()
            .filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
        return asked.isEmpty || asked == "1" || asked == "test" ? "test" : asked
    }()

    /// A test run there to be weighed and timed rather than driven
    /// (ANT_MEASURE beside ANT_PROBE). It keeps what the shipped
    /// browser does where test runs otherwise differ — hidden pages slowed
    /// the way WebKit slows them, App Nap left to macOS — so what gets
    /// measured is what people get.
    static var measuring: Bool {
        testing && ProcessInfo.processInfo.environment["ANT_MEASURE"] != nil
    }

    /// Cookies, sign-ins, caches. WebKit keeps its default store per bundle,
    /// not per folder, so a test run got every site already signed in — and
    /// "sign out of everything" in a test run signed the real browser out.
    /// A test run gets a store of its own, under a fixed name so it persists
    /// between probes the way the real one does. Wiping the test store is
    /// then as safe as wiping its folder.
    static var websites: WKWebsiteDataStore {
        guard testing, !ownContainer else { return .default() }
        return WKWebsiteDataStore(forIdentifier: probeStore(1))
    }

    /// A test copy of the app under a bundle id of its own has a WebKit
    /// container of its own too, so it can use WebKit's default store and
    /// extension configuration — the ones the real browser uses, which
    /// differ from stores made by identifier in how long extension workers
    /// are let live.
    static var ownContainer: Bool {
        (Bundle.main.bundleIdentifier ?? "") != "com.vedant.ant"
    }

    /// The fixed identifiers of a test world's WebKit stores: 1 for websites,
    /// 2 for extensions. The test world's are 5E4C0000-0000-4000-8000-00000000000k,
    /// the ones fresh.sh wipes; a named world puts a hash of its name (FNV-1a,
    /// 32 bits) in place of the second and third groups of zeros, so each
    /// keeps its own from one run to the next.
    static func probeStore(_ kind: UInt32) -> UUID {
        var hash: UInt32 = 0
        if let world, world != "test" {
            hash = 2_166_136_261
            for byte in world.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        }
        let text = String(format: "5E4C%04X-%04X-4000-8000-%012X", hash >> 16, hash & 0xFFFF, kind)
        return UUID(uuidString: text)!
    }

    /// Ant is made from Search (Office Commun's browser, which was Office
    /// Browser before that). The first time Ant runs, what Search kept — the
    /// session, the pins, history, bookmarks, what is hidden on each site,
    /// the extensions — is copied across. Copied, not moved: Search may
    /// still be on this Mac, and still in use.
    static let folder: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let home = support.appendingPathComponent(world.map { "Ant (\($0))" } ?? "Ant", isDirectory: true)
        if !testing {
            let files = FileManager.default
            let before = ["Search", "Office Browser"]
                .map { support.appendingPathComponent($0, isDirectory: true) }
                .first { files.fileExists(atPath: $0.path) }
            if !files.fileExists(atPath: home.path), let before {
                // Into a folder beside it first, and only then under Ant's
                // name: a copy that failed halfway would otherwise stand as
                // Ant's folder, and the next launch would never try again.
                let partial = support.appendingPathComponent("Ant.partial", isDirectory: true)
                try? files.removeItem(at: partial)
                do {
                    try files.copyItem(at: before, to: partial)
                    // Search's own socket for scripts is no use to Ant.
                    try? files.removeItem(at: partial.appendingPathComponent("bench.sock"))
                    try files.moveItem(at: partial, to: home)
                } catch {
                    NSLog("Ant: couldn't bring %@ across: %@", before.path, error.localizedDescription)
                    try? files.removeItem(at: partial)
                }
            }
        }
        return home
    }()

    static func file(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    /// A file that didn't decode is set aside rather than overwritten the
    /// next time something is saved over it — bookmarks, history and a
    /// session are the kind of thing nobody wants to lose to a bad read with
    /// no trace of what was there. Failing to move it is fine: the read
    /// already came back empty either way, and there's nothing further to
    /// do about a folder that won't take a rename.
    static func quarantine(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.deletingPathExtension().lastPathComponent).unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: file, to: aside)
    }

    /// Settings live apart too: a test that changes what the tabs wear or
    /// where the tabs go must not change yours.
    static let settings: UserDefaults = {
        guard testing else {
            carryOver(into: .standard)
            return .standard
        }
        let suite = world == "test" ? "com.vedant.ant.test" : "com.vedant.ant.test.\(world ?? "")"
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    /// Search's settings, read once and written under Ant's own name. A
    /// setting Ant already has is Ant's; the rest come as they were.
    private static func carryOver(into fresh: UserDefaults) {
        guard !fresh.bool(forKey: "carried.search") else { return }
        fresh.set(true, forKey: "carried.search")
        guard let old = UserDefaults(suiteName: "com.officecommun.search") else { return }
        // What only meant something to Search: its updater, its script
        // socket's consent, and whether its passkey entitlement was seen.
        let skipped: Set<String> = ["bench", "passkeys.entitled", "update.skipped", "carried"]
        for (key, value) in old.persistentDomain(forName: "com.officecommun.search") ?? [:]
        where fresh.object(forKey: key) == nil && !key.hasPrefix("NS") && !key.hasPrefix("Apple")
            && !key.hasPrefix("update") && !skipped.contains(key) {
            fresh.set(value, forKey: key)
        }
        // The window comes back where it was, under its new name.
        if let frame = old.string(forKey: "NSWindow Frame search") {
            fresh.set(frame, forKey: "NSWindow Frame ant")
        }
    }
}
