import Foundation

// Account metadata lives in accounts.json (source of truth). The ~/.mbsyncrc
// "managed block" is regenerated from it, so the existing sync engine — which
// discovers accounts from Channel lines — needs no changes.

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case gmail
    case icloud
    case imap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .icloud: return "iCloud"
        case .imap: return "IMAP"
        }
    }

    var defaultHost: String {
        switch self {
        case .gmail: return "imap.gmail.com"
        case .icloud: return "imap.mail.me.com"
        case .imap: return ""
        }
    }

    var defaultPort: Int { 993 }

    // Where the user gets an app-specific password for this type.
    var passwordHelp: String {
        switch self {
        case .gmail:
            return "Turn on 2-Step Verification, then create an app password."
        case .icloud:
            return "Create an app-specific password for your Apple Account."
        case .imap:
            return "Use your IMAP password, or an app password if your provider requires one."
        }
    }

    // Page where the user creates an app-specific password.
    var passwordCreateURL: URL? {
        switch self {
        case .gmail: return URL(string: "https://myaccount.google.com/apppasswords")
        case .icloud: return URL(string: "https://account.apple.com")
        case .imap: return nil
        }
    }

    // Support article explaining the process.
    var passwordSupportURL: URL? {
        switch self {
        case .gmail: return URL(string: "https://support.google.com/accounts/answer/185833")
        case .icloud: return URL(string: "https://support.apple.com/102654")
        case .imap: return nil
        }
    }
}

struct MailAccount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var slug: String = ""
    var type: AccountType = .gmail
    var email: String = ""
    var host: String = ""
    var port: Int = 993
    var tlsType: String = "IMAPS"
    var authMechs: String = "LOGIN"
    var patterns: String = "*"
    var maxSize: String = ""   // empty = unlimited; e.g. "50m"
    var folder: String = ""    // empty = <archiveBase>/<slug>; else an explicit path
}

struct AccountsConfig: Codable {
    var archiveBase: String = "~/MailArchive"
    var accounts: [MailAccount] = []
}

enum MbsyncConfig {
    static let beginMarker = "# >>> aMail managed — do not edit by hand >>>"
    static let endMarker = "# <<< aMail managed <<<"

    // name -> url-safe slug: lowercase, non [a-z0-9] -> '-', collapse, trim.
    static func makeSlug(_ name: String) -> String {
        var out = ""
        var lastDash = false
        for scalar in name.lowercased().unicodeScalars {
            let isAllowed = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAllowed {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func keychainService(slug: String) -> String {
        "aMail: \(slug)"
    }

    // Resolved Maildir path for an account: its explicit folder, or <base>/<slug>.
    static func maildirPath(for account: MailAccount, archiveBase: String) -> String {
        let folder = account.folder.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty {
            let expanded = expand(folder)
            return expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
        }
        return "\(expand(archiveBase))/\(account.slug)"
    }

    // mbsync stanzas for one account. archiveBase is the (possibly ~-prefixed) root.
    static func stanza(for account: MailAccount, archiveBase: String) -> String {
        let slug = account.slug
        let path = maildirPath(for: account, archiveBase: archiveBase)
        let service = keychainService(slug: slug)
        let passCmd = "security find-generic-password -s '\(service)' -a '\(account.email)' -w"

        var lines: [String] = []
        lines.append("IMAPAccount \(slug)")
        lines.append("  Host \(account.host)")
        lines.append("  Port \(account.port)")
        lines.append("  User \(account.email)")
        lines.append("  PassCmd \"\(passCmd)\"")
        lines.append("  TLSType \(account.tlsType)")
        if !account.authMechs.isEmpty {
            lines.append("  AuthMechs \(account.authMechs)")
        }
        lines.append("")
        lines.append("IMAPStore \(slug)-remote")
        lines.append("  Account \(slug)")
        lines.append("")
        lines.append("MaildirStore \(slug)-local")
        lines.append("  Path \(path)/")
        lines.append("  Inbox \(path)/Inbox")
        lines.append("  SubFolders Verbatim")
        lines.append("")
        lines.append("Channel \(slug)")
        lines.append("  Far :\(slug)-remote:")
        lines.append("  Near :\(slug)-local:")
        lines.append("  Patterns \(account.patterns.isEmpty ? "*" : account.patterns)")
        lines.append("  Create Near")
        lines.append("  Expunge None")
        lines.append("  Remove None")
        lines.append("  SyncState *")
        if !account.maxSize.isEmpty {
            lines.append("  MaxSize \(account.maxSize)")
        }
        return lines.joined(separator: "\n")
    }

    static func managedBlock(accounts: [MailAccount], archiveBase: String) -> String {
        let body = accounts
            .map { stanza(for: $0, archiveBase: archiveBase) }
            .joined(separator: "\n\n")
        return "\(beginMarker)\n\(body)\n\(endMarker)\n"
    }

    // Replace the managed region in `existing` with `block`, preserving everything
    // outside it. If no markers are present, append the block.
    static func merge(existing: String, block: String) -> String {
        guard let beginRange = existing.range(of: beginMarker),
              let endRange = existing.range(of: endMarker),
              beginRange.lowerBound < endRange.lowerBound else {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return block
            }
            return "\(trimmed)\n\n\(block)"
        }

        let before = String(existing[existing.startIndex..<beginRange.lowerBound])
        let after = String(existing[endRange.upperBound...])
        let trimmedAfter = after.drop(while: { $0 == "\n" })
        let prefix = before.isEmpty ? "" : before
        return "\(prefix)\(block)\(trimmedAfter.isEmpty ? "" : "\n\(trimmedAfter)")"
    }

    // Channel names in mbsyncrc text — mirrors the shell discovery, used by tests.
    static func channelNames(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0] == "Channel" else { return nil }
            return String(parts[1])
        }
    }
}

// MARK: - Validation

struct AccountValidation {
    static func errors(for account: MailAccount, existing: [MailAccount]) -> [String] {
        var problems: [String] = []

        if account.name.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Name is required.")
        }
        if account.slug.isEmpty {
            problems.append("Slug is required.")
        } else if account.slug != MbsyncConfig.makeSlug(account.slug) {
            problems.append("Slug may contain only lowercase letters, digits, and dashes.")
        }
        if existing.contains(where: { $0.id != account.id && $0.slug == account.slug }) {
            problems.append("Slug “\(account.slug)” is already in use.")
        }
        if !account.email.contains("@") || account.email.hasSuffix("@") || account.email.hasPrefix("@") {
            problems.append("A valid email address is required.")
        }
        if account.host.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Host is required.")
        }
        if account.port < 1 || account.port > 65535 {
            problems.append("Port must be between 1 and 65535.")
        }
        return problems
    }
}

// MARK: - Keychain (via the `security` CLI)

enum Keychain {
    @discardableResult
    static func setPassword(_ password: String, slug: String, email: String) -> Bool {
        run([
            "add-generic-password",
            "-U",
            "-s", MbsyncConfig.keychainService(slug: slug),
            "-a", email,
            "-w", password,
            "-T", "/usr/bin/security"
        ])
    }

    @discardableResult
    static func deletePassword(slug: String, email: String) -> Bool {
        run([
            "delete-generic-password",
            "-s", MbsyncConfig.keychainService(slug: slug),
            "-a", email
        ])
    }

    static func readPassword(slug: String, email: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", MbsyncConfig.keychainService(slug: slug),
            "-a", email,
            "-w"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    private static func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Credential test (let mbsync do the talking)

struct CredentialTestResult {
    let ok: Bool
    let message: String
}

enum CredentialTester {
    static func test(account: MailAccount, password: String, mbsyncPath: String) -> CredentialTestResult {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("amail-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let mailDir = tmpRoot.appendingPathComponent("mail", isDirectory: true)
        let configURL = tmpRoot.appendingPathComponent("mbsyncrc")
        do {
            try FileManager.default.createDirectory(at: mailDir, withIntermediateDirectories: true)
        } catch {
            return CredentialTestResult(ok: false, message: "Could not create a temporary directory.")
        }

        let authLine = account.authMechs.isEmpty ? "" : "\nAuthMechs \(account.authMechs)"
        let config = """
        IMAPAccount probe
        Host \(account.host)
        Port \(account.port)
        User \(account.email)
        Pass "\(password)"
        TLSType \(account.tlsType)\(authLine)

        IMAPStore probe-remote
        Account probe

        MaildirStore probe-local
        Path \(mailDir.path)/
        Inbox \(mailDir.path)/Inbox

        Channel probe
        Far :probe-remote:
        Near :probe-local:
        Patterns "INBOX"
        """

        do {
            try config.write(to: configURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configURL.path
            )
        } catch {
            return CredentialTestResult(ok: false, message: "Could not write the test config.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mbsyncPath)
        process.arguments = ["-c", configURL.path, "--list", "probe"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment

        let errPipe = Pipe()
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CredentialTestResult(ok: false, message: "Could not run mbsync.")
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return CredentialTestResult(ok: true, message: "Connected and authenticated.")
        }

        let stderr = String(data: errData, encoding: .utf8) ?? ""
        let lower = stderr.lowercased()
        if lower.contains("authenticationfailed") || lower.contains("login failed")
            || lower.contains("invalid credentials") || lower.contains("authentication failed") {
            return CredentialTestResult(ok: false, message: "Authentication failed — check the email and app password.")
        }
        let detail = stderr
            .split(separator: "\n")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return CredentialTestResult(ok: false, message: detail?.isEmpty == false ? detail! : "Connection failed.")
    }
}

// MARK: - Persistence + side effects

final class AccountRepository {
    let accountsURL: URL
    let mbsyncConfigURL: URL

    init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aMail", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.accountsURL = appSupport.appendingPathComponent("accounts.json")

        let envConfig = ProcessInfo.processInfo.environment["MBSYNC_CONFIG"]
        if let envConfig, !envConfig.isEmpty {
            self.mbsyncConfigURL = URL(fileURLWithPath: envConfig)
        } else {
            self.mbsyncConfigURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".mbsyncrc")
        }
    }

    func load() -> AccountsConfig {
        guard let data = try? Data(contentsOf: accountsURL),
              let config = try? JSONDecoder().decode(AccountsConfig.self, from: data) else {
            return AccountsConfig()
        }
        return config
    }

    // Persist metadata, regenerate the mbsyncrc managed block, ensure Maildirs exist.
    func save(_ config: AccountsConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: accountsURL, options: .atomic)

        try applyToMbsyncrc(config)
        createMaildirs(config)
    }

    func applyToMbsyncrc(_ config: AccountsConfig) throws {
        let existing = (try? String(contentsOf: mbsyncConfigURL, encoding: .utf8)) ?? ""
        let block = MbsyncConfig.managedBlock(accounts: config.accounts, archiveBase: config.archiveBase)
        let merged = MbsyncConfig.merge(existing: existing, block: block)
        try merged.write(to: mbsyncConfigURL, atomically: true, encoding: .utf8)
    }

    func createMaildirs(_ config: AccountsConfig) {
        for account in config.accounts {
            let path = MbsyncConfig.maildirPath(for: account, archiveBase: config.archiveBase)
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
        }
    }

    func renameStore(fromPath: String, toPath: String) throws {
        if FileManager.default.fileExists(atPath: fromPath) {
            let to = URL(fileURLWithPath: toPath)
            try FileManager.default.createDirectory(
                at: to.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: URL(fileURLWithPath: fromPath), to: to)
        }
    }

    func deleteStore(path: String) throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }

    func locateMbsync() -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(dir)/mbsync"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // notmuch must index the archive base for counts/search to work.
    func notmuchCoversBase(_ config: AccountsConfig) -> Bool {
        guard let dbPath = notmuchDatabasePath() else { return false }
        let base = MbsyncConfig.expand(config.archiveBase)
        let normalizedDB = dbPath.hasSuffix("/") ? String(dbPath.dropLast()) : dbPath
        return base == normalizedDB || base.hasPrefix(normalizedDB + "/")
    }

    func notmuchDatabasePath() -> String? {
        let env = ProcessInfo.processInfo.environment["NOTMUCH_CONFIG"]
        let configURL: URL
        if let env, !env.isEmpty {
            configURL = URL(fileURLWithPath: env)
        } else {
            configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".notmuch-config")
        }
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("path") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return MbsyncConfig.expand(parts[1].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }
}

// MARK: - Self-test (aMail --self-test)

enum AMailSelfTest {
    static func run() -> Int32 {
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        // Slug derivation
        check(MbsyncConfig.makeSlug("Work Gmail") == "work-gmail", "slug spaces")
        check(MbsyncConfig.makeSlug("  Alex's iCloud!! ") == "alex-s-icloud", "slug punctuation")
        check(MbsyncConfig.makeSlug("UPPER_case 99") == "upper-case-99", "slug mixed")

        // Stanza generation
        var account = MailAccount()
        account.slug = "work"
        account.email = "me@example.com"
        account.host = "imap.gmail.com"
        account.port = 993
        let stanza = MbsyncConfig.stanza(for: account, archiveBase: "/tmp/Mail")
        check(stanza.contains("Channel work"), "stanza has channel")
        check(stanza.contains("Path /tmp/Mail/work/"), "stanza has maildir path")
        check(stanza.contains("PassCmd \"security find-generic-password -s 'aMail: work' -a 'me@example.com' -w\""),
              "stanza has passcmd")
        check(stanza.contains("Expunge None") && stanza.contains("Remove None"), "stanza archive-safe")

        // Channel discovery round-trips
        let names = MbsyncConfig.channelNames(in: stanza)
        check(names == ["work"], "channel discovered")

        // Per-account folder: default vs explicit override
        check(MbsyncConfig.maildirPath(for: account, archiveBase: "/tmp/Mail") == "/tmp/Mail/work",
              "maildir default path")
        var custom = account
        custom.folder = "/srv/mail/work-archive/"
        check(MbsyncConfig.maildirPath(for: custom, archiveBase: "/tmp/Mail") == "/srv/mail/work-archive",
              "maildir explicit path")
        check(MbsyncConfig.stanza(for: custom, archiveBase: "/tmp/Mail").contains("Path /srv/mail/work-archive/"),
              "stanza honors explicit folder")

        // Managed-block merge preserves foreign content
        let foreign = "# my hand-written config\nIMAPAccount legacy\n  Host x\n"
        let block = MbsyncConfig.managedBlock(accounts: [account], archiveBase: "/tmp/Mail")
        let merged = MbsyncConfig.merge(existing: foreign, block: block)
        check(merged.contains("IMAPAccount legacy"), "merge keeps foreign")
        check(merged.contains(MbsyncConfig.beginMarker) && merged.contains(MbsyncConfig.endMarker),
              "merge has markers")

        // Re-merge replaces, does not duplicate, the managed block
        var account2 = account
        account2.slug = "work2"
        let block2 = MbsyncConfig.managedBlock(accounts: [account2], archiveBase: "/tmp/Mail")
        let remerged = MbsyncConfig.merge(existing: merged, block: block2)
        check(remerged.components(separatedBy: MbsyncConfig.beginMarker).count == 2, "merge idempotent markers")
        check(remerged.contains("Channel work2") && !remerged.contains("Channel work\n"), "merge replaced body")
        check(remerged.contains("IMAPAccount legacy"), "re-merge keeps foreign")

        // Validation
        var bad = MailAccount()
        bad.name = ""
        bad.slug = "Bad Slug"
        bad.email = "nope"
        bad.host = ""
        let problems = AccountValidation.errors(for: bad, existing: [])
        check(problems.count >= 4, "validation flags bad input")

        // Keychain service derivation
        check(MbsyncConfig.keychainService(slug: "work") == "aMail: work", "keychain service name")

        print(failed == 0 ? "all passed" : "FAILURES: \(failed)")
        return failed == 0 ? 0 : 1
    }
}

