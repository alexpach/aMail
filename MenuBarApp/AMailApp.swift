import AppKit
import Darwin
import Foundation

private let agentName = "amail-agent"

struct AccountDownloadStats {
    let account: String
    let lastHour: Int
    let last24Hours: Int
    let last7Days: Int
    let last30Days: Int
}

struct MailboxStats {
    let total: String
    let unread: String
    let inbox: String
    let status: String
    let hasMenuCounts: Bool

    static let unavailable = MailboxStats(
        total: "n/a",
        unread: "n/a",
        inbox: "n/a",
        status: "notmuch count unavailable",
        hasMenuCounts: false
    )

    var menuSummary: String? {
        guard hasMenuCounts else { return nil }

        let messageWord = total == "1" ? "message" : "messages"
        return "\(total) \(messageWord) | \(unread) unread"
    }
}

struct RequirementsSnapshot {
    let mbsyncPath: String?
    let notmuchPath: String?
    let mbsyncConfigPath: String
    let mbsyncConfigReadable: Bool
    let mbsyncChannelCount: Int

    var canSync: Bool {
        mbsyncPath != nil && notmuchPath != nil && mbsyncConfigReadable && mbsyncChannelCount > 0
    }

    var summary: String {
        let missing = missingItems
        if missing.isEmpty {
            return "Ready"
        }

        return "Missing \(missing.joined(separator: ", "))"
    }

    var detail: String {
        if canSync {
            let label = mbsyncChannelCount == 1 ? "channel" : "channels"
            return "mbsync and notmuch found; \(mbsyncChannelCount) \(label)"
        }

        return summary
    }

    private var missingItems: [String] {
        var items: [String] = []
        if mbsyncPath == nil {
            items.append("mbsync")
        }
        if notmuchPath == nil {
            items.append("notmuch")
        }
        if !mbsyncConfigReadable {
            items.append("mbsync config")
        } else if mbsyncChannelCount == 0 {
            items.append("mbsync channels")
        }
        return items
    }
}

struct StatsSnapshot {
    let syncState: String
    let processState: String
    let launchAtLoginState: String
    let newMailWindows: AccountDownloadStats
    let mailboxStats: MailboxStats
    let requirements: RequirementsSnapshot
    let lastAccountSync: String
    let lastAccountSyncDisplay: String
    let lastIndexing: String
    let lastIssue: String
    let accountDownloadStats: [AccountDownloadStats]
    let accountActivity: [(account: String, detail: String)]
    let logPath: String
    let accountSyncInProgress: Bool

    static let empty = StatsSnapshot(
        syncState: "Unknown",
        processState: "Unknown",
        launchAtLoginState: "Unknown",
        newMailWindows: AccountDownloadStats(
            account: "All accounts",
            lastHour: 0,
            last24Hours: 0,
            last7Days: 0,
            last30Days: 0
        ),
        mailboxStats: .unavailable,
        requirements: RequirementsSnapshot(
            mbsyncPath: nil,
            notmuchPath: nil,
            mbsyncConfigPath: "",
            mbsyncConfigReadable: false,
            mbsyncChannelCount: 0
        ),
        lastAccountSync: "No data",
        lastAccountSyncDisplay: "Last sync: never",
        lastIndexing: "No data",
        lastIssue: "No data",
        accountDownloadStats: [],
        accountActivity: [],
        logPath: "",
        accountSyncInProgress: false
    )
}

final class AccountStatsTableView: NSView {
    private let accountColumnWidth: CGFloat
    private let numberColumnWidth: CGFloat
    private let fontSize: CGFloat
    private let rowsStack = NSStackView()

    init(accountColumnWidth: CGFloat, numberColumnWidth: CGFloat, fontSize: CGFloat) {
        self.accountColumnWidth = accountColumnWidth
        self.numberColumnWidth = numberColumnWidth
        self.fontSize = fontSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 4
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ stats: [AccountDownloadStats]) {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        rowsStack.addArrangedSubview(row(account: "Account", values: ["1h", "24h", "7d", "30d"], isHeader: true))

        if stats.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No account stats yet")
            emptyLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
            emptyLabel.textColor = .secondaryLabelColor
            rowsStack.addArrangedSubview(emptyLabel)
            return
        }

        for stat in stats {
            rowsStack.addArrangedSubview(row(
                account: stat.account,
                values: [
                    "\(stat.lastHour)",
                    "\(stat.last24Hours)",
                    "\(stat.last7Days)",
                    "\(stat.last30Days)"
                ],
                isHeader: false
            ))
        }
    }

    private func row(account: String, values: [String], isHeader: Bool) -> NSView {
        let accountLabel = label(account, isHeader: isHeader, alignment: .left)
        accountLabel.lineBreakMode = .byTruncatingMiddle

        let valueLabels = values.map { label($0, isHeader: isHeader, alignment: .right) }
        let row = NSStackView(views: [accountLabel] + valueLabels)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            accountLabel.widthAnchor.constraint(equalToConstant: accountColumnWidth)
        ] + valueLabels.map {
            $0.widthAnchor.constraint(equalToConstant: numberColumnWidth)
        })

        return row
    }

    private func label(_ value: String, isHeader: Bool, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = isHeader
            ? NSFont.systemFont(ofSize: fontSize, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        label.textColor = isHeader ? .secondaryLabelColor : .labelColor
        label.alignment = alignment
        return label
    }
}

final class DashboardView: NSView {
    private let syncValue = DashboardView.valueLabel()
    private let processValue = DashboardView.valueLabel()
    private let launchValue = DashboardView.valueLabel()
    private let newMailValue = DashboardView.largeValueLabel()
    private let totalMailValue = DashboardView.largeValueLabel()
    private let unreadValue = DashboardView.largeValueLabel()
    private let inboxValue = DashboardView.detailValueLabel()
    private let mailboxStatusValue = DashboardView.detailValueLabel()
    private let requirementsValue = DashboardView.detailValueLabel()
    private let configValue = DashboardView.detailValueLabel()
    private let lastSyncValue = DashboardView.detailValueLabel()
    private let lastIndexingValue = DashboardView.detailValueLabel()
    private let lastIssueValue = DashboardView.detailValueLabel()
    private let logPathValue = DashboardView.detailValueLabel()
    private let accountStatsTable = AccountStatsTableView(accountColumnWidth: 230, numberColumnWidth: 72, fontSize: 12)
    private let accountActivityStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Stats")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let topRow = NSStackView(views: [
            Self.metricPanel(title: "Sync", valueLabel: syncValue),
            Self.metricPanel(title: "Process", valueLabel: processValue),
            Self.metricPanel(title: "New Mail 24h", valueLabel: newMailValue),
            Self.metricPanel(title: "Mailbox Total", valueLabel: totalMailValue),
            Self.metricPanel(title: "Unread", valueLabel: unreadValue)
        ])
        topRow.orientation = .horizontal
        topRow.alignment = .top
        topRow.distribution = .fillEqually
        topRow.spacing = 10
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let detailGrid = NSGridView(views: [
            [Self.detailLabel("Launch at Login"), launchValue],
            [Self.detailLabel("Inbox"), inboxValue],
            [Self.detailLabel("Mailbox counts"), mailboxStatusValue],
            [Self.detailLabel("Dependencies"), requirementsValue],
            [Self.detailLabel("mbsync config"), configValue],
            [Self.detailLabel("Last sync"), lastSyncValue],
            [Self.detailLabel("Last indexing"), lastIndexingValue],
            [Self.detailLabel("Last issue"), lastIssueValue],
            [Self.detailLabel("Log file"), logPathValue]
        ])
        detailGrid.translatesAutoresizingMaskIntoConstraints = false
        detailGrid.rowSpacing = 6
        detailGrid.columnSpacing = 12
        detailGrid.xPlacement = .leading
        detailGrid.column(at: 0).xPlacement = .trailing
        detailGrid.column(at: 1).xPlacement = .fill
        detailGrid.column(at: 1).width = 650

        let downloadsTitle = NSTextField(labelWithString: "New mail by account")
        downloadsTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let activityTitle = NSTextField(labelWithString: "Latest account activity")
        activityTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        accountActivityStack.orientation = .vertical
        accountActivityStack.alignment = .leading
        accountActivityStack.spacing = 4
        accountActivityStack.translatesAutoresizingMaskIntoConstraints = false

        let outerStack = NSStackView(views: [titleLabel, topRow, detailGrid, downloadsTitle, accountStatsTable, activityTitle, accountActivityStack])
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            topRow.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            detailGrid.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            accountStatsTable.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            accountActivityStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ snapshot: StatsSnapshot) {
        syncValue.stringValue = snapshot.syncState
        processValue.stringValue = snapshot.processState
        launchValue.stringValue = snapshot.launchAtLoginState
        newMailValue.stringValue = "\(snapshot.newMailWindows.last24Hours)"
        totalMailValue.stringValue = snapshot.mailboxStats.total
        unreadValue.stringValue = snapshot.mailboxStats.unread
        inboxValue.stringValue = snapshot.mailboxStats.inbox
        mailboxStatusValue.stringValue = snapshot.mailboxStats.status
        requirementsValue.stringValue = snapshot.requirements.detail
        configValue.stringValue = snapshot.requirements.mbsyncConfigPath
        lastSyncValue.stringValue = snapshot.lastAccountSync
        lastIndexingValue.stringValue = snapshot.lastIndexing
        lastIssueValue.stringValue = snapshot.lastIssue
        logPathValue.stringValue = snapshot.logPath
        accountStatsTable.update(snapshot.accountDownloadStats)

        for view in accountActivityStack.arrangedSubviews {
            accountActivityStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if snapshot.accountActivity.isEmpty {
            let emptyLabel = Self.detailValueLabel()
            emptyLabel.stringValue = "No account activity yet"
            accountActivityStack.addArrangedSubview(emptyLabel)
        } else {
            for activity in snapshot.accountActivity.prefix(6) {
                accountActivityStack.addArrangedSubview(Self.activityRow(account: activity.account, detail: activity.detail))
            }
        }
    }

    private static func metricPanel(title: String, valueLabel: NSTextField) -> NSView {
        let panel = NSBox()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.titlePosition = .noTitle
        panel.contentViewMargins = NSSize(width: 10, height: 8)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let stackView = NSStackView(views: [titleLabel, valueLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = panel.contentView ?? panel
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            panel.heightAnchor.constraint(equalToConstant: 66),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        return panel
    }

    private static func activityRow(account: String, detail: String) -> NSView {
        let accountLabel = detailLabel(account)
        accountLabel.lineBreakMode = .byTruncatingMiddle
        let detailLabel = detailValueLabel()
        detailLabel.stringValue = detail

        let row = NSStackView(views: [accountLabel, detailLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            accountLabel.widthAnchor.constraint(equalToConstant: 180)
        ])

        return row
    }

    private static func detailLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func valueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        return label
    }

    private static func largeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func detailValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        return label
    }
}

final class TextWindowController: NSWindowController {
    private let dashboardView = DashboardView(frame: .zero)
    private let logTextView = NSTextView(frame: .zero)
    private let statsProvider: () -> StatsSnapshot
    private let logProvider: () -> String
    private var refreshTimer: Timer?
    private var lastLogText = ""

    init(title: String, statsProvider: @escaping () -> StatsSnapshot, logProvider: @escaping () -> String) {
        self.statsProvider = statsProvider
        self.logProvider = logProvider

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()

        let contentView = NSView()

        let logLabel = NSTextField(labelWithString: "Live Log")
        logLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let logScrollView = Self.makeScrollView(textView: logTextView)
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let stackView = NSStackView(views: [dashboardView, logLabel, logScrollView])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            dashboardView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            logScrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])

        super.init(window: window)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    @objc func refresh() {
        dashboardView.update(statsProvider())
        updateLogText(logProvider())
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(logTextView)
        window?.orderFrontRegardless()
    }

    private static func makeScrollView(textView: NSTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.autoresizingMask = [.height]
        scrollView.documentView = textView
        return scrollView
    }

    private func updateLogText(_ newText: String) {
        guard newText != lastLogText else {
            if isNearBottom(logTextView) && !hasActiveSelection(logTextView) {
                scrollLogToBottom(preserveHorizontalOffset: true)
            }
            return
        }

        let wasNearBottom = isNearBottom(logTextView)
        let hadSelection = hasActiveSelection(logTextView)
        let selectedRanges = logTextView.selectedRanges
        let visibleOrigin = visibleOrigin(in: logTextView)

        if newText.hasPrefix(lastLogText), !lastLogText.isEmpty {
            let delta = String(newText.dropFirst(lastLogText.count))
            logTextView.textStorage?.append(NSAttributedString(string: delta))
        } else {
            logTextView.textStorage?.replaceCharacters(
                in: NSRange(location: 0, length: logTextView.string.utf16.count),
                with: newText
            )
        }
        lastLogText = newText

        if wasNearBottom && !hadSelection {
            scrollLogToBottom(preserveHorizontalOffset: true)
        } else {
            restoreSelection(selectedRanges)
            restoreVisibleOrigin(visibleOrigin)
        }
    }

    private func isNearBottom(_ textView: NSTextView) -> Bool {
        guard let scrollView = textView.enclosingScrollView else {
            return true
        }

        ensureLogLayout()
        let visibleMaxY = scrollView.contentView.documentVisibleRect.maxY
        let documentHeight = scrollView.documentView?.bounds.height ?? textView.bounds.height
        return documentHeight - visibleMaxY < 80
    }

    private func hasActiveSelection(_ textView: NSTextView) -> Bool {
        textView.selectedRanges.contains { value in
            value.rangeValue.length > 0
        }
    }

    private func visibleOrigin(in textView: NSTextView) -> NSPoint {
        textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
    }

    private func restoreSelection(_ ranges: [NSValue]) {
        let textLength = logTextView.string.utf16.count
        let validRanges = ranges.filter { value in
            let range = value.rangeValue
            return range.location != NSNotFound && range.location + range.length <= textLength
        }

        if !validRanges.isEmpty {
            logTextView.selectedRanges = validRanges
        }
    }

    private func restoreVisibleOrigin(_ origin: NSPoint) {
        guard let scrollView = logTextView.enclosingScrollView else { return }

        ensureLogLayout()
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let visibleSize = scrollView.contentView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let clampedOrigin = NSPoint(
            x: min(max(0, origin.x), maxX),
            y: min(max(0, origin.y), maxY)
        )

        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scrollLogToBottom(preserveHorizontalOffset: Bool) {
        guard let scrollView = logTextView.enclosingScrollView else { return }

        ensureLogLayout()
        let currentX = scrollView.contentView.bounds.origin.x
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let visibleSize = scrollView.contentView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let targetX = preserveHorizontalOffset ? min(currentX, maxX) : 0

        scrollView.contentView.scroll(to: NSPoint(x: targetX, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func ensureLogLayout() {
        guard let layoutManager = logTextView.layoutManager,
              let textContainer = logTextView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
    }
}

struct LogEntry {
    let timestamp: String
    let actor: String
    let action: String
}

final class LogStore {
    let logURL: URL
    private var cachedEntries: [LogEntry] = []
    private var cachedSignature: FileSignature?

    private struct FileSignature: Equatable {
        let size: Int
        let modified: Date
    }

    init(logURL: URL) {
        self.logURL = logURL
    }

    private struct RollingDownloadStats {
        var lastHour = 0
        var last24Hours = 0
        var last7Days = 0
        var last30Days = 0

        mutating func add(count: Int, eventDate: Date, now: Date) {
            let age = now.timeIntervalSince(eventDate)
            guard age >= 0 else { return }

            if age <= 3_600 {
                lastHour += count
            }
            if age <= 86_400 {
                last24Hours += count
            }
            if age <= 604_800 {
                last7Days += count
            }
            if age <= 2_592_000 {
                last30Days += count
            }
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    func tail(lineCount: Int = 300) -> String {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            return "No log file found at:\n\(logURL.path)"
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineCount).joined(separator: "\n")
    }

    func entries() -> [LogEntry] {
        let signature = fileSignature()
        if let signature, signature == cachedSignature {
            return cachedEntries
        }

        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            cachedEntries = []
            cachedSignature = signature
            return []
        }

        let parsed = content.split(separator: "\n").compactMap { rawLine -> LogEntry? in
            let parts = rawLine.components(separatedBy: ": ")
            guard parts.count >= 3 else { return nil }
            return LogEntry(
                timestamp: parts[0],
                actor: parts[1],
                action: parts.dropFirst(2).joined(separator: ": ")
            )
        }
        cachedEntries = parsed
        cachedSignature = signature
        return parsed
    }

    private func fileSignature() -> FileSignature? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path) else {
            return nil
        }
        return FileSignature(
            size: (attrs[.size] as? Int) ?? 0,
            modified: (attrs[.modificationDate] as? Date) ?? .distantPast
        )
    }

    func snapshot(
        syncStatus: String,
        syncEnabled: Bool,
        launchAtLogin: Bool,
        mailboxStats: MailboxStats,
        requirements: RequirementsSnapshot
    ) -> StatsSnapshot {
        let entries = self.entries()
        let now = Date()
        var totalNewMailStats = RollingDownloadStats()
        var lastIndexing: LogEntry?
        var lastAccountSync: LogEntry?
        var lastIssue: LogEntry?
        var latestByAccount: [String: LogEntry] = [:]
        var accountNames = Set<String>()
        var rollingByAccount: [String: RollingDownloadStats] = [:]

        for entry in entries {
            if Self.isAccountActor(entry.actor) {
                accountNames.insert(entry.actor)
                latestByAccount[entry.actor] = entry
            }

            if entry.action.hasPrefix("Indexing completed:") {
                lastIndexing = entry
            }
            if Self.isAccountActor(entry.actor) && entry.action == "Sync finished" {
                lastAccountSync = entry
            }
            if Self.isIssue(entry.action) {
                lastIssue = entry
            }

            guard Self.isAccountActor(entry.actor),
                  let count = Self.downloadCount(from: entry.action),
                  let date = Self.logDate(from: entry.timestamp) else {
                continue
            }

            var stats = rollingByAccount[entry.actor] ?? RollingDownloadStats()
            stats.add(count: count, eventDate: date, now: now)
            rollingByAccount[entry.actor] = stats
            totalNewMailStats.add(count: count, eventDate: date, now: now)
        }

        var accountDownloadStats = [
            AccountDownloadStats(
                account: "All accounts",
                lastHour: totalNewMailStats.lastHour,
                last24Hours: totalNewMailStats.last24Hours,
                last7Days: totalNewMailStats.last7Days,
                last30Days: totalNewMailStats.last30Days
            )
        ]
        accountDownloadStats += accountNames.sorted().map { account -> AccountDownloadStats in
            let stats = rollingByAccount[account] ?? RollingDownloadStats()
            return AccountDownloadStats(
                account: account,
                lastHour: stats.lastHour,
                last24Hours: stats.last24Hours,
                last7Days: stats.last7Days,
                last30Days: stats.last30Days
            )
        }

        let accountActivity = latestByAccount.keys.sorted().compactMap { account -> (account: String, detail: String)? in
            guard let entry = latestByAccount[account] else { return nil }
            return (account: account, detail: "\(entry.timestamp): \(entry.action)")
        }

        let accountSyncInProgress = entries
            .reversed()
            .first { Self.isAccountActor($0.actor) }?
            .action == "Sync started"

        return StatsSnapshot(
            syncState: syncEnabled ? "On" : "Off",
            processState: syncStatus,
            launchAtLoginState: launchAtLogin ? "On" : "Off",
            newMailWindows: AccountDownloadStats(
                account: "All accounts",
                lastHour: totalNewMailStats.lastHour,
                last24Hours: totalNewMailStats.last24Hours,
                last7Days: totalNewMailStats.last7Days,
                last30Days: totalNewMailStats.last30Days
            ),
            mailboxStats: mailboxStats,
            requirements: requirements,
            lastAccountSync: lastAccountSync.map { "\($0.timestamp): \($0.actor)" } ?? "No completed sync yet",
            lastAccountSyncDisplay: lastAccountSync.map { Self.lastSyncDisplay(for: $0, now: now) } ?? "Last sync: never",
            lastIndexing: lastIndexing.map { Self.entrySummary($0) } ?? "No indexing event yet",
            lastIssue: lastIssue.map { Self.entrySummary($0) } ?? "No recent issues",
            accountDownloadStats: accountDownloadStats,
            accountActivity: accountActivity,
            logPath: logURL.path,
            accountSyncInProgress: accountSyncInProgress
        )
    }

    private static func logDate(from timestamp: String) -> Date? {
        logDateFormatter.date(from: timestamp)
    }

    private static func lastSyncDisplay(for entry: LogEntry, now: Date) -> String {
        guard let date = logDate(from: entry.timestamp) else {
            return "Last sync: \(entry.timestamp)"
        }

        let age = max(0, now.timeIntervalSince(date))
        if age > 172_800 {
            return "Last sync: \(entry.timestamp)"
        }
        if age < 60 {
            return "Last sync: just now"
        }
        if age < 3_600 {
            let minutes = max(1, Int(age / 60))
            return "Last sync: \(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
        }

        let hours = max(1, Int(age / 3_600))
        return "Last sync: \(hours) \(hours == 1 ? "hour" : "hours") ago"
    }

    private static func isAccountActor(_ actor: String) -> Bool {
        actor != agentName &&
            actor != "mail-sync-agent" &&
            actor != "Notmuch indexing"
    }

    private static func downloadCount(from action: String) -> Int? {
        guard action.hasPrefix("Downloaded ") else { return nil }
        let pieces = action.split(separator: " ")
        guard pieces.count >= 2 else { return nil }
        return Int(pieces[1])
    }

    private static func isIssue(_ action: String) -> Bool {
        action.contains("Network unavailable") ||
            action.contains("Quota backoff") ||
            action.contains("Connection error") ||
            action.contains("Sync failed") ||
            action.contains("Indexing failed") ||
            action.contains("Already running") ||
            action.contains("Failed to start sync") ||
            action.contains("Could not stop")
    }

    private static func entrySummary(_ entry: LogEntry) -> String {
        "\(entry.timestamp): \(entry.actor): \(entry.action)"
    }
}

final class MailboxStatsProvider {
    private let refreshInterval: TimeInterval = 30
    private var cachedStats: MailboxStats?
    private var lastRefresh: Date?

    private let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private let statusFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func snapshot() -> MailboxStats {
        let now = Date()
        if let cachedStats,
           let lastRefresh,
           now.timeIntervalSince(lastRefresh) < refreshInterval {
            return cachedStats
        }

        let total = count(query: "*")
        let unread = count(query: "tag:unread")
        let inbox = count(query: "tag:inbox")
        let stats: MailboxStats

        if total == nil && unread == nil && inbox == nil {
            stats = .unavailable
        } else {
            stats = MailboxStats(
                total: formatted(total),
                unread: formatted(unread),
                inbox: formatted(inbox),
                status: "updated \(statusFormatter.string(from: now))",
                hasMenuCounts: total != nil && unread != nil
            )
        }

        cachedStats = stats
        lastRefresh = now
        return stats
    }

    private func count(query: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["notmuch", "count", query]
        process.environment = countEnvironment()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.flatMap(Int.init)
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else {
            return "n/a"
        }

        return countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func countEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(fallbackPath):\(path)"
        } else {
            environment["PATH"] = fallbackPath
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        if environment["HOME"]?.isEmpty ?? true {
            environment["HOME"] = homeURL.path
        }

        let notmuchConfigURL = homeURL.appendingPathComponent(".notmuch-config")
        if environment["NOTMUCH_CONFIG"]?.isEmpty ?? true,
           FileManager.default.isReadableFile(atPath: notmuchConfigURL.path) {
            environment["NOTMUCH_CONFIG"] = notmuchConfigURL.path
        }

        return environment
    }
}

final class RequirementsProvider {
    private let mbsyncConfigURL: URL
    private let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    init(mbsyncConfigURL: URL) {
        self.mbsyncConfigURL = mbsyncConfigURL
    }

    func snapshot() -> RequirementsSnapshot {
        let channels = mbsyncChannels()
        return RequirementsSnapshot(
            mbsyncPath: executablePath(named: "mbsync"),
            notmuchPath: executablePath(named: "notmuch"),
            mbsyncConfigPath: mbsyncConfigURL.path,
            mbsyncConfigReadable: FileManager.default.isReadableFile(atPath: mbsyncConfigURL.path),
            mbsyncChannelCount: channels.count
        )
    }

    private func executablePath(named name: String) -> String? {
        for directory in searchPaths {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func mbsyncChannels() -> [String] {
        guard let content = try? String(contentsOf: mbsyncConfigURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#") else { return nil }
                let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 2, parts[0] == "Channel" else { return nil }
                return String(parts[1])
            }
    }
}

final class StatusHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Sync: disabled")
    private let detailLabel = NSTextField(labelWithString: "Last sync: never")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 64))

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle

        let stackView = NSStackView(views: [titleLabel, detailLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(syncState: String, lastSyncText: String) {
        titleLabel.stringValue = "Sync: \(syncState)"
        titleLabel.textColor = .labelColor
        detailLabel.stringValue = lastSyncText
    }
}

final class MenuStatsView: NSView {
    private let statusSummary = NSTextField(labelWithString: "")
    private let downloadedTitle = NSTextField(labelWithString: "New mail")
    private let downloadedTable = AccountStatsTableView(accountColumnWidth: 152, numberColumnWidth: 34, fontSize: 11)

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 104))

        statusSummary.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusSummary.lineBreakMode = .byTruncatingMiddle
        downloadedTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let stackView = NSStackView(views: [statusSummary, downloadedTitle, downloadedTable])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            statusSummary.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            downloadedTable.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ snapshot: StatsSnapshot) {
        let summaryParts = [snapshot.requirements.summary] + [snapshot.mailboxStats.menuSummary].compactMap { $0 }
        statusSummary.stringValue = summaryParts.joined(separator: " | ")
        statusSummary.textColor = snapshot.requirements.canSync ? .secondaryLabelColor : .systemRed
        downloadedTable.update(snapshot.accountDownloadStats)
        let downloadedRows = max(2, snapshot.accountDownloadStats.count + 1)
        frame.size = NSSize(width: 360, height: CGFloat(68 + downloadedRows * 18))
    }
}

final class LoginAgent {
    static let label = "com.archive-mail.amail"

    static var plistURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func isEnabled(for executableURL: URL) -> Bool {
        guard let content = try? String(contentsOf: plistURL, encoding: .utf8) else {
            return false
        }
        return content.contains(executableURL.path)
    }

    static func setEnabled(_ enabled: Bool, executableURL: URL, workingDirectory: URL) throws {
        if enabled {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executableURL.path],
                "RunAtLoad": true,
                "KeepAlive": false,
                "WorkingDirectory": workingDirectory.path,
                "EnvironmentVariables": [
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                ]
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
        } else {
            _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
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

@MainActor
final class SyncController {
    private let syncEnabledKey = "SyncEnabled"
    private let defaults = UserDefaults.standard

    let repoRoot: URL
    let scriptURL: URL
    let logURL: URL
    let verboseLogURL: URL
    let lockURL: URL
    let mbsyncConfigURL: URL

    private var syncProcess: Process?

    init(repoRoot: URL) {
        let logsURL = repoRoot.appendingPathComponent("logs", isDirectory: true)
        let tmpURL = repoRoot.appendingPathComponent("tmp", isDirectory: true)
        let environmentConfig = ProcessInfo.processInfo.environment["MBSYNC_CONFIG"]
        let configPath = environmentConfig?.isEmpty == false
            ? environmentConfig!
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".mbsyncrc")
                .path

        self.repoRoot = repoRoot
        self.scriptURL = Self.resolveScriptURL(repoRoot: repoRoot)
        self.logURL = logsURL.appendingPathComponent("mail-sync.log")
        self.verboseLogURL = logsURL.appendingPathComponent("mail-sync.verbose.log")
        self.lockURL = tmpURL.appendingPathComponent("mail-sync.lock/pid")
        self.mbsyncConfigURL = URL(fileURLWithPath: configPath)
    }

    var syncEnabled: Bool {
        defaults.bool(forKey: syncEnabledKey)
    }

    var executableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/aMail")
    }

    var launchAtLoginEnabled: Bool {
        LoginAgent.isEnabled(for: executableURL)
    }

    func enableSync() {
        defaults.set(true, forKey: syncEnabledKey)
        appendAgentLog("Menu app enabled sync")
        startSyncIfNeeded()
    }

    func disableSync() {
        defaults.set(false, forKey: syncEnabledKey)
        appendAgentLog("Menu app disabled sync")
        stopSync()
    }

    func startSyncIfNeeded() {
        guard !isChildSyncRunning else { return }
        if externalSyncPID() != nil {
            return
        }

        startSync(arguments: [], logAction: "Menu app started sync")
    }

    @discardableResult
    func runNow() -> Bool {
        if let pid = childSyncPID() {
            if kill(pid, SIGUSR1) == 0 {
                appendAgentLog("Menu app requested run now")
                return true
            }

            appendAgentLog("Failed to request run now for pid \(pid): errno \(errno)")
            return false
        }

        if let pid = externalSyncPID() {
            appendAgentLog("Run now unavailable: sync is running outside app, pid \(pid)")
            return false
        }

        if syncEnabled {
            startSyncIfNeeded()
            return isChildSyncRunning
        }

        return startSync(arguments: ["--once"], logAction: "Menu app started one-time sync")
    }

    @discardableResult
    private func startSync(arguments: [String], logAction: String) -> Bool {
        let process = configuredProcess(arguments: arguments)
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncProcess = nil
            }
        }

        do {
            try process.run()
            syncProcess = process
            appendAgentLog(logAction)
            return true
        } catch {
            appendAgentLog("Failed to start sync: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func stopSync() -> Bool {
        var ok = true

        if let process = syncProcess, process.isRunning {
            process.terminate()
            appendAgentLog("Menu app stopped sync")
        }
        syncProcess = nil

        if let pid = externalSyncPID() {
            if kill(pid, SIGTERM) != 0 {
                ok = false
                appendAgentLog("Could not stop external sync pid \(pid): errno \(errno)")
            }
        }

        return ok
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try LoginAgent.setEnabled(enabled, executableURL: executableURL, workingDirectory: repoRoot)
    }

    var isChildSyncRunning: Bool {
        syncProcess?.isRunning == true
    }

    var isExternalSyncRunning: Bool {
        externalSyncPID() != nil
    }

    var isAnySyncRunning: Bool {
        isChildSyncRunning || externalSyncPID() != nil
    }

    func statusText() -> String {
        if isChildSyncRunning {
            return "running"
        }
        if let pid = externalSyncPID() {
            if syncEnabled {
                return "enabled; external sync running, pid \(pid)"
            }
            return "disabled; external sync running, pid \(pid)"
        }
        if syncEnabled {
            return "enabled, not running"
        }
        return "disabled"
    }

    // A release .app bundles the script in Resources; a dev build runs it from the checkout.
    static func resolveScriptURL(repoRoot: URL) -> URL {
        if let bundled = Bundle.main.url(forResource: "mail-sync", withExtension: "sh") {
            return bundled
        }
        return repoRoot.appendingPathComponent("mail-sync.sh")
    }

    // mbsync's modern-bash features need Homebrew bash; pick whichever arch installed it.
    static func resolveBashURL() -> URL {
        for path in ["/opt/homebrew/bin/bash", "/usr/local/bin/bash"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/bash")
    }

    private func configuredProcess(arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = Self.resolveBashURL()
        process.arguments = [scriptURL.path] + arguments
        process.currentDirectoryURL = repoRoot
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "PROJECT_DIR": repoRoot.path,
            "MBSYNC_CONFIG": mbsyncConfigURL.path,
            "LOG_DIR": logURL.deletingLastPathComponent().path,
            "TMP_DIR": lockURL.deletingLastPathComponent().deletingLastPathComponent().path
        ]
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        return process
    }

    private func childSyncPID() -> pid_t? {
        guard let process = syncProcess, process.isRunning else {
            return nil
        }

        return process.processIdentifier
    }

    private func externalSyncPID() -> pid_t? {
        guard let content = try? String(contentsOf: lockURL, encoding: .utf8),
              let rawPID = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)),
              rawPID > 0 else {
            return nil
        }

        if let process = syncProcess, process.processIdentifier == rawPID, process.isRunning {
            return nil
        }

        if kill(rawPID, 0) == 0 || errno == EPERM {
            return rawPID
        }

        return nil
    }

    func appendAgentLog(_ action: String) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let line = "\(formatter.string(from: now)): \(agentName): \(action)\n"

        if let data = line.data(using: .utf8) {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusHeaderView = StatusHeaderView()
    private let menuStatsView = MenuStatsView()
    private var toggleSyncItem: NSMenuItem!
    private var runNowItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var shimmerTimer: Timer?
    private var shimmerStep = 0
    private var logsWindow: TextWindowController?

    private lazy var controller = SyncController(repoRoot: Self.resolveRuntimeRoot())
    private lazy var logStore = LogStore(logURL: controller.logURL)
    private lazy var requirementsProvider = RequirementsProvider(mbsyncConfigURL: controller.mbsyncConfigURL)
    private let mailboxStatsProvider = MailboxStatsProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        if controller.syncEnabled && requirementsProvider.snapshot().canSync {
            controller.startSyncIfNeeded()
        }
        controller.appendAgentLog("Menu app started")

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenu()
            }
        }
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        shimmerTimer?.invalidate()
        if controller.isChildSyncRunning {
            controller.stopSync()
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "aMail") {
                image.isTemplate = true
                button.image = image
            }
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "aMail"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let statusHeaderItem = NSMenuItem()
        statusHeaderItem.view = statusHeaderView
        menu.addItem(statusHeaderItem)

        let statsItem = NSMenuItem()
        statsItem.view = menuStatsView
        menu.addItem(statsItem)

        menu.addItem(.separator())

        toggleSyncItem = NSMenuItem(title: "Turn Sync On", action: #selector(toggleSync), keyEquivalent: "")
        toggleSyncItem.target = self
        menu.addItem(toggleSyncItem)

        runNowItem = NSMenuItem(title: "Run Now", action: #selector(runNow), keyEquivalent: "r")
        runNowItem.target = self
        runNowItem.toolTip = "Start a sync pass now"
        menu.addItem(runNowItem)

        let logsItem = NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        let configItem = NSMenuItem(title: "Open mbsync Config", action: #selector(openMbsyncConfig), keyEquivalent: ",")
        configItem.target = self
        configItem.toolTip = "Open the mbsync configuration file"
        menu.addItem(configItem)

        menu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateMenu() {
        let requirements = requirementsProvider.snapshot()
        if controller.syncEnabled && !controller.isAnySyncRunning && requirements.canSync {
            controller.startSyncIfNeeded()
        }

        let status = controller.statusText()
        let isRunning = controller.isAnySyncRunning
        let snapshot = logStore.snapshot(
            syncStatus: status,
            syncEnabled: controller.syncEnabled,
            launchAtLogin: controller.launchAtLoginEnabled,
            mailboxStats: mailboxStatsProvider.snapshot(),
            requirements: requirements
        )
        statusHeaderView.update(
            syncState: Self.headerSyncState(syncEnabled: controller.syncEnabled, isRunning: isRunning),
            lastSyncText: snapshot.lastAccountSyncDisplay
        )
        menuStatsView.update(snapshot)
        statusItem.button?.toolTip = "aMail: \(status); \(snapshot.lastAccountSyncDisplay)"
        updateStatusIcon(syncEnabled: controller.syncEnabled, syncInProgress: isRunning && snapshot.accountSyncInProgress)

        toggleSyncItem.title = controller.syncEnabled ? "Turn Sync Off" : "Turn Sync On"
        toggleSyncItem.state = .off

        runNowItem.isEnabled = requirements.canSync && !snapshot.accountSyncInProgress && !controller.isExternalSyncRunning

        launchAtLoginItem.state = controller.launchAtLoginEnabled ? .on : .off
    }

    private static func headerSyncState(syncEnabled: Bool, isRunning: Bool) -> String {
        if isRunning {
            return "running"
        }
        return syncEnabled ? "enabled" : "disabled"
    }

    private func updateStatusIcon(syncEnabled: Bool, syncInProgress: Bool) {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.imagePosition = .imageOnly

        if syncInProgress {
            startStatusIconShimmer()
        } else {
            stopStatusIconShimmer(syncEnabled: syncEnabled)
        }
    }

    private func startStatusIconShimmer() {
        guard shimmerTimer == nil else { return }

        shimmerStep = 0
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStatusIconShimmer()
            }
        }
        shimmerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStatusIconShimmer(syncEnabled: Bool) {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
        shimmerStep = 0
        statusItem.button?.alphaValue = syncEnabled ? 1.0 : 0.42
    }

    private func advanceStatusIconShimmer() {
        shimmerStep = (shimmerStep + 1) % 24
        let progress = Double(shimmerStep) / 23.0
        let wave = (sin(progress * Double.pi * 2.0 - Double.pi / 2.0) + 1.0) / 2.0
        statusItem.button?.alphaValue = 0.52 + CGFloat(wave) * 0.48
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    @objc private func toggleSync() {
        if controller.syncEnabled {
            controller.disableSync()
        } else {
            let requirements = requirementsProvider.snapshot()
            guard requirements.canSync else {
                showRequirementsError(requirements)
                updateMenu()
                return
            }
            controller.enableSync()
        }
        updateMenu()
    }

    @objc private func runNow() {
        let requirements = requirementsProvider.snapshot()
        guard requirements.canSync else {
            showRequirementsError(requirements)
            updateMenu()
            return
        }

        if !controller.runNow() {
            showError("Run Now Failed", "Could not start or request a sync pass. Check the log for details.")
        }
        updateMenu()
    }

    @objc private func openMbsyncConfig() {
        let url = controller.mbsyncConfigURL
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            showError("mbsync Config Not Found", "aMail expected a readable mbsync config at:\n\(url.path)")
            return
        }

        if !NSWorkspace.shared.open(url) {
            showError("Could Not Open Config", "aMail could not open:\n\(url.path)")
        }
    }

    @objc private func openLogs() {
        if logsWindow == nil {
            logsWindow = TextWindowController(title: "aMail Logs") { [weak self] in
                guard let self else { return .empty }
                return self.logStore.snapshot(
                    syncStatus: self.controller.statusText(),
                    syncEnabled: self.controller.syncEnabled,
                    launchAtLogin: self.controller.launchAtLoginEnabled,
                    mailboxStats: self.mailboxStatsProvider.snapshot(),
                    requirements: self.requirementsProvider.snapshot()
                )
            } logProvider: { [weak self] in
                self?.logStore.tail() ?? "No log data"
            }
        }
        logsWindow?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try controller.setLaunchAtLogin(!controller.launchAtLoginEnabled)
        } catch {
            showError("Launch at Login Failed", error.localizedDescription)
        }
        updateMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showRequirementsError(_ requirements: RequirementsSnapshot) {
        showError(
            "aMail Is Not Ready",
            "\(requirements.summary).\n\nInstall mbsync and notmuch, then make sure your mbsync config is readable at:\n\(requirements.mbsyncConfigPath)"
        )
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentPID = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        if let existing = others.first {
            existing.activate(options: [])
            return false
        }

        return true
    }

    // Runtime root holds logs/ and tmp/. An installed app (script bundled inside it)
    // keeps them in Application Support; a dev build keeps them in the checkout.
    private static func resolveRuntimeRoot() -> URL {
        if Bundle.main.url(forResource: "mail-sync", withExtension: "sh") != nil {
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/aMail", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }

        if let resourceURL = Bundle.main.url(forResource: "RepoRoot", withExtension: "txt"),
           let path = try? String(contentsOf: resourceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let bundleURL = Bundle.main.bundleURL
        let buildDirectory = bundleURL.deletingLastPathComponent()
        return buildDirectory.deletingLastPathComponent()
    }
}

@main
struct AMailApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
