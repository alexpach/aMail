import AppKit
import SwiftUI

@MainActor
final class AccountStore: ObservableObject {
    @Published var config: AccountsConfig
    @Published var lastError: String?
    @Published var notmuchWarning: String?

    let repository = AccountRepository()

    init() {
        config = repository.load()
        refreshNotmuchWarning()
    }

    var mbsyncPath: String? { repository.locateMbsync() }

    func account(withID id: UUID) -> MailAccount? {
        config.accounts.first { $0.id == id }
    }

    @discardableResult
    func save(account: MailAccount, password: String, original: MailAccount?, renameStoreFolder: Bool) -> Bool {
        let others = config.accounts.filter { $0.id != account.id }
        let problems = AccountValidation.errors(for: account, existing: config.accounts)
        if !problems.isEmpty {
            lastError = problems.joined(separator: "\n")
            return false
        }

        if let original, original.slug != account.slug {
            let pw = password.isEmpty
                ? Keychain.readPassword(slug: original.slug, email: original.email)
                : password
            if let pw { Keychain.setPassword(pw, slug: account.slug, email: account.email) }
            Keychain.deletePassword(slug: original.slug, email: original.email)
            if renameStoreFolder {
                try? repository.renameStore(base: config.archiveBase, oldSlug: original.slug, newSlug: account.slug)
            }
        } else if !password.isEmpty {
            Keychain.setPassword(password, slug: account.slug, email: account.email)
        }

        var updated = others
        updated.append(account)
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist(updated)
        return lastError == nil
    }

    func delete(_ account: MailAccount, deleteStoreFolder: Bool) {
        Keychain.deletePassword(slug: account.slug, email: account.email)
        if deleteStoreFolder {
            try? repository.deleteStore(base: config.archiveBase, slug: account.slug)
        }
        persist(config.accounts.filter { $0.id != account.id })
    }

    func setArchiveBase(_ path: String) {
        config.archiveBase = path
        persist(config.accounts)
    }

    private func persist(_ accounts: [MailAccount]) {
        config.accounts = accounts
        do {
            try repository.save(config)
            lastError = nil
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
        }
        refreshNotmuchWarning()
    }

    private func refreshNotmuchWarning() {
        if config.accounts.isEmpty || repository.notmuchCoversBase(config) {
            notmuchWarning = nil
        } else {
            let base = config.archiveBase
            notmuchWarning = "notmuch is not indexing \(base). "
                + "Set database.path in ~/.notmuch-config to \(base) so search and counts work."
        }
    }
}

struct AccountsView: View {
    @EnvironmentObject var store: AccountStore
    @State private var selection: UUID?
    @State private var editing: MailAccount?
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Accounts") {
                    if store.config.accounts.isEmpty {
                        Text("No accounts yet. Click + to add one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.config.accounts) { account in
                        HStack {
                            Image(systemName: icon(for: account.type))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name).fontWeight(.medium)
                                Text("\(account.email) · \(account.slug)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(account.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(account.id)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = account }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $isAdding) {
            AccountEditor(original: nil).environmentObject(store)
        }
        .sheet(item: $editing) { account in
            AccountEditor(original: account).environmentObject(store)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = store.notmuchWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    if let id = selection, let account = store.account(withID: id) {
                        confirmDelete(account)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Archive folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(store.config.archiveBase)
                            .font(.caption.monospaced())
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Button("Choose…") { chooseArchiveFolder() }
                    }
                }
            }
        }
        .padding(12)
    }

    private func icon(for type: AccountType) -> String {
        switch type {
        case .gmail: return "envelope"
        case .icloud: return "icloud"
        case .imap: return "tray.full"
        }
    }

    private func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            store.setArchiveBase(url.path)
        }
    }

    private func confirmDelete(_ account: MailAccount) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(account.name)”?"
        alert.informativeText = "This removes the account from mbsync. "
            + "Its local mail archive can be kept or deleted."
        alert.addButton(withTitle: "Remove Account")
        alert.addButton(withTitle: "Remove + Delete Archive")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.delete(account, deleteStoreFolder: false)
            selection = nil
        case .alertSecondButtonReturn:
            store.delete(account, deleteStoreFolder: true)
            selection = nil
        default:
            break
        }
    }
}

struct AccountEditor: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss

    let original: MailAccount?

    @State private var draft: MailAccount
    @State private var password = ""
    @State private var slugEditedManually = false
    @State private var showAdvanced = false
    @State private var testing = false
    @State private var testResult: CredentialTestResult?

    init(original: MailAccount?) {
        self.original = original
        if let original {
            _draft = State(initialValue: original)
            _slugEditedManually = State(initialValue: true)
        } else {
            var fresh = MailAccount()
            fresh.host = AccountType.gmail.defaultHost
            fresh.port = AccountType.gmail.defaultPort
            _draft = State(initialValue: fresh)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .onChange(of: draft.name) { _, newValue in
                            if !slugEditedManually {
                                draft.slug = MbsyncConfig.makeSlug(newValue)
                            }
                        }
                    Picker("Type", selection: $draft.type) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: draft.type) { _, newType in
                        draft.host = newType.defaultHost
                        draft.port = newType.defaultPort
                    }
                }

                Section("Login") {
                    TextField("Email", text: $draft.email)
                    SecureField(original == nil ? "App password" : "App password (blank = keep)", text: $password)
                    Text(draft.type.passwordHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = draft.type.passwordHelpURL {
                        Link("How to create an app password →", destination: url)
                            .font(.caption)
                    }
                    if draft.type == .imap {
                        TextField("Host", text: $draft.host)
                        portField
                    }
                }

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    HStack {
                        TextField("Slug", text: $draft.slug)
                            .onChange(of: draft.slug) { _, _ in slugEditedManually = true }
                        Text("folder & channel name").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.type != .imap {
                        TextField("Host", text: $draft.host)
                        portField
                    }
                    TextField("TLS type", text: $draft.tlsType)
                    TextField("Auth mechanisms", text: $draft.authMechs)
                    TextField("Patterns", text: $draft.patterns)
                    TextField("Max size (e.g. 50m, blank = unlimited)", text: $draft.maxSize)
                }

                if let result = testResult {
                    Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.ok ? .green : .red)
                        .font(.caption)
                }
                if let error = store.lastError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button {
                    runTest()
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text("Test") }
                }
                .disabled(testing || password.isEmpty || draft.email.isEmpty || draft.host.isEmpty)

                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
    }

    private var portField: some View {
        TextField("Port", value: $draft.port, format: .number.grouping(.never))
    }

    private func runTest() {
        guard let mbsyncPath = store.mbsyncPath else {
            testResult = CredentialTestResult(ok: false, message: "mbsync not found. Install it with: brew install isync")
            return
        }
        testing = true
        testResult = nil
        let account = draft
        let pw = password
        Task.detached {
            let result = CredentialTester.test(account: account, password: pw, mbsyncPath: mbsyncPath)
            await MainActor.run {
                testResult = result
                testing = false
            }
        }
    }

    private func saveDraft() {
        if !slugEditedManually || draft.slug.isEmpty {
            draft.slug = MbsyncConfig.makeSlug(draft.slug.isEmpty ? draft.name : draft.slug)
        }

        var renameFolder = false
        if let original, original.slug != draft.slug {
            let alert = NSAlert()
            alert.messageText = "Rename archive folder to “\(draft.slug)”?"
            alert.informativeText = "The slug changed. aMail can move the existing local mail "
                + "folder and update all paths, or leave the old folder in place."
            alert.addButton(withTitle: "Rename Folder")
            alert.addButton(withTitle: "Keep Old Folder")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: renameFolder = true
            case .alertSecondButtonReturn: renameFolder = false
            default: return
            }
        }

        if store.save(account: draft, password: password, original: original, renameStoreFolder: renameFolder) {
            dismiss()
        }
    }
}
