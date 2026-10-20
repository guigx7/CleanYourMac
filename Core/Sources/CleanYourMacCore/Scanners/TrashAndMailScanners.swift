import Foundation

private func listChildren(_ dir: URL) -> [URL] {
    let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
    return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func isDirectory(_ u: URL) -> Bool {
    (try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
}

private func isPackage(_ u: URL) -> Bool {
    (try? u.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
}

// MARK: - Lixos

/// Lixo do usuário (e do iCloud) e lixos dos volumes montados (docs/re/specs/trash.md).
public struct TrashScanner: ScopedScanner {
    public let group = GroupID.trash
    private let volumes: any VolumeProvider
    private let sizer = FileSizer()

    public init(volumes: any VolumeProvider = SystemVolumes()) {
        self.volumes = volumes
    }

    func systemTrashes(_ ctx: ScanContext) -> [URL] {
        var dirs = ["~/.Trash", "~/Library/Mobile Documents/com~apple~CloudDocs/.Trash",
                    "~/Library/CloudStorage/iCloud Drive/.Trash", "~/Library/Mobile Documents/.Trash"].map(ctx.resolve)
        dirs += listChildren(ctx.resolve("~/Library/Mobile Documents")).map { $0.appendingPathComponent("Documents/.Trash") }
        var seen = Set<String>()
        return dirs.filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert(PathPolicy.realPath($0.path)).inserted }
    }

    func volumeTrashes(_ ctx: ScanContext) -> [(MountedVolume, URL)] {
        let prefix = PathPolicy.realPath(ctx.resolve("/Volumes").path).lowercased() + "/"
        return volumes.mountedVolumes().compactMap { v in
            guard PathPolicy.realPath(v.url.path).lowercased().hasPrefix(prefix), v.isBrowsable, v.isLocal, !v.isReadOnly else { return nil }
            let dir = v.url.appendingPathComponent(".Trashes/\(ctx.uid)")
            return FileManager.default.fileExists(atPath: dir.path) ? (v, dir) : nil
        }
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: systemTrashes(context) + volumeTrashes(context).map(\.1))
    }

    private func items(in dir: URL) -> [JunkItem] {
        listChildren(dir).map { u in
            JunkItem(group: group, name: u.lastPathComponent, url: u, size: sizer.allocatedSize(of: u),
                     isRecommended: true, icon: .file(u), removal: .delete(u))
        }
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var out: [JunkItem] = []
        let system = systemTrashes(context).flatMap { dir -> [JunkItem] in
            report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
            return items(in: dir)
        }
        if !system.isEmpty {
            out.append(JunkItem(id: "trash:system", group: group, name: "Trash", url: nil, size: 0,
                                icon: .symbol("internaldrive"), children: system, titleKey: "trash.system"))
        }
        let mounted = volumeTrashes(context).compactMap { volume, dir -> JunkItem? in
            report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
            let children = items(in: dir)
            guard !children.isEmpty else { return nil }
            return JunkItem(id: "trash:volume:\(volume.url.path)", group: group, name: volume.name, url: volume.url, size: 0,
                            icon: .symbol("externaldrive"), children: children)
        }
        if !mounted.isEmpty {
            out.append(JunkItem(id: "trash:mounted", group: group, name: "Mounted trashes", url: nil, size: 0,
                                icon: .symbol("externaldrive"), children: mounted, titleKey: "trash.mounted"))
        }
        return out
    }
}

// MARK: - Anexos do Mail

/// Anexos das contas IMAP e downloads do Mail (docs/re/specs/mail-attachments.md).
public struct MailAttachmentsScanner: ScopedScanner {
    public let group = GroupID.mailAttachments
    private let accounts: any MailAccountSource
    private let sizer = FileSizer()
    private static let uuidPattern = #"^\w{8}(-\w{4}){3}-\w{12}$"#

    public init(accounts: any MailAccountSource = SQLiteMailAccounts()) {
        self.accounts = accounts
    }

    static func downloadDirs(_ ctx: ScanContext) -> [URL] {
        ["~/Library/Mail Downloads", "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"].map(ctx.resolve)
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: Self.downloadDirs(context) + (MailLibrary.versionDirectory(context).map { [$0] } ?? []))
    }

    static func isOffline(_ accountDir: URL) -> Bool {
        let plist = accountDir.appendingPathComponent(".mboxCache.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = dict["takenOffline"] else { return false }
        if let b = value as? Bool { return b }
        return ["yes", "true", "1"].contains("\(value)".lowercased())
    }

    /// Arquivos/pacotes dentro de toda pasta `Attachments` da conta.
    private func attachmentFiles(_ accountDir: URL) -> [URL] {
        var out: [URL] = []
        func walk(_ dir: URL, insideAttachments: Bool) {
            for u in listChildren(dir) where !u.lastPathComponent.hasPrefix(".") {
                if RuleBasedScanner.isSymlink(u) { continue }
                if isDirectory(u) && !isPackage(u) {
                    let opens = insideAttachments || u.lastPathComponent.lowercased() == "attachments"
                    walk(u, insideAttachments: opens)
                } else if insideAttachments {
                    out.append(u)
                }
            }
        }
        walk(accountDir, insideAttachments: false)
        return out
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var out: [JunkItem] = []
        if let version = MailLibrary.versionDirectory(context) {
            for account in accounts.accounts(context) where account.isIMAP && account.isActive {
                try Task.checkCancellation()
                let dir = version.appendingPathComponent(account.identifier)
                guard !Self.isOffline(dir) else { continue }
                report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
                var order: [String] = []
                var copies: [String: [URL]] = [:]
                for file in attachmentFiles(dir) {
                    let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let key = "\(file.lastPathComponent)-\(bytes)"
                    if copies[key] == nil { order.append(key) }
                    copies[key, default: []].append(file)
                }
                let attachments = order.map { key -> JunkItem in
                    let files = copies[key]!
                    let leaves = files.map { f in
                        JunkItem(group: group, name: f.lastPathComponent, url: f, size: sizer.allocatedSize(of: f),
                                 isRecommended: true, icon: .file(f), removal: .delete(f))
                    }
                    if leaves.count == 1 {
                        let l = leaves[0]
                        return JunkItem(id: "mailAttachments:\(account.identifier):\(key)", group: group, name: l.name, url: l.url,
                                        size: l.size, isRecommended: true, icon: l.icon, removal: l.removal)
                    }
                    return JunkItem(id: "mailAttachments:\(account.identifier):\(key)", group: group, name: files[0].lastPathComponent,
                                    url: nil, size: 0, icon: .file(files[0]), children: leaves)
                }
                guard !attachments.isEmpty else { continue }
                out.append(JunkItem(id: "mailAttachments:\(account.identifier)", group: group, name: account.name, url: nil,
                                    size: 0, icon: .symbol("envelope"), children: attachments))
            }
        }
        let downloads = Self.downloadDirs(context).flatMap(listChildren).filter { $0.lastPathComponent != ".DS_Store" }.map { child -> JunkItem in
            var representative = child
            if isDirectory(child), child.lastPathComponent.range(of: Self.uuidPattern, options: .regularExpression) != nil,
               let last = listChildren(child).last {
                representative = last
            }
            let values = try? representative.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let created = values?.creationDate?.timeIntervalSince1970 ?? 0
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return JunkItem(id: "mailAttachments:downloads:\(child.path)", group: group, name: representative.lastPathComponent,
                            url: child, size: sizer.allocatedSize(of: child), isRecommended: created == modified,
                            icon: .file(representative), removal: .delete(child))
        }
        if !downloads.isEmpty {
            out.append(JunkItem(id: "mailAttachments:downloads", group: group, name: "Mail Downloads", url: nil, size: 0,
                                icon: .symbol("envelope"), children: downloads, titleKey: "mail.downloads"))
        }
        return out
    }
}

// MARK: - Lixo do Mail

/// Mensagens nas caixas de Lixo das contas IMAP (docs/re/specs/mail-trash.md).
public struct MailTrashScanner: ScopedScanner {
    public let group = GroupID.mailTrash
    private let accounts: any MailAccountSource
    private let sizer = FileSizer()

    public init(accounts: any MailAccountSource = SQLiteMailAccounts()) {
        self.accounts = accounts
    }

    func trashBoxes(_ ctx: ScanContext) -> [(MailAccount, URL)] {
        guard let version = MailLibrary.versionDirectory(ctx) else { return [] }
        return accounts.accounts(ctx).compactMap { account in
            guard account.isIMAP, account.isActive, let name = account.trashMailboxName, !name.isEmpty else { return nil }
            let box = name.split(separator: "/").reduce(version.appendingPathComponent(account.identifier)) {
                $0.appendingPathComponent("\($1).mbox")
            }
            return FileManager.default.fileExists(atPath: box.path) ? (account, box) : nil
        }
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: trashBoxes(context).map(\.1))
    }

    /// `.emlx`/`.emlxpart` dentro das pastas `Data` da caixa.
    private func messages(_ box: URL) -> [URL] {
        var out: [URL] = []
        func walk(_ dir: URL, insideData: Bool) {
            for u in listChildren(dir) where !u.lastPathComponent.hasPrefix(".") && !RuleBasedScanner.isSymlink(u) {
                if isDirectory(u) && !isPackage(u) {
                    walk(u, insideData: insideData || u.lastPathComponent.lowercased() == "data")
                } else if insideData, ["emlx", "emlxpart"].contains(u.pathExtension.lowercased()) {
                    out.append(u)
                }
            }
        }
        walk(box, insideData: false)
        return out
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let envelope = MailLibrary.versionDirectory(context)
            .flatMap { SQLiteReader(url: $0.appendingPathComponent("MailData/Envelope Index")) }
        return try trashBoxes(context).compactMap { account, box in
            try Task.checkCancellation()
            report(ScanProgress(group: group, currentPath: box.path, bytesFound: 0))
            let msgs = messages(box).map { file -> JunkItem in
                let stem = file.deletingPathExtension().lastPathComponent
                let attachments = listChildren(file.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Attachments/\(stem)")).flatMap(listChildren).map { a in
                        JunkItem(group: group, name: a.lastPathComponent, url: a, size: sizer.allocatedSize(of: a),
                                 isRecommended: true, icon: .file(a), removal: .delete(a))
                    }
                let message = JunkItem(id: "mailTrash:\(file.path)#message", group: group, name: file.lastPathComponent, url: file,
                                       size: sizer.allocatedSize(of: file), isRecommended: true,
                                       icon: .symbol("envelope"), removal: .delete(file))
                let name = Self.title(Int64(stem), envelope) ?? file.lastPathComponent
                return JunkItem(id: "mailTrash:\(file.path)", group: group, name: name, url: file, size: 0,
                                icon: .symbol("envelope"), children: [message] + attachments, displaysChildren: !attachments.isEmpty)
            }
            guard !msgs.isEmpty else { return nil }
            return JunkItem(id: "mailTrash:\(account.identifier)", group: group, name: account.name, url: nil, size: 0,
                            icon: .symbol("envelope.badge"), children: msgs)
        }
    }

    /// "<remetente>: <assunto>" a partir do Envelope Index; `nil` se faltar algum.
    static func title(_ id: Int64?, _ db: SQLiteReader?) -> String? {
        guard let id, let db else { return nil }
        let rows = db.query("""
            SELECT s.subject, a.comment, a.address FROM messages m
            LEFT JOIN subjects s ON s.ROWID = m.subject LEFT JOIN addresses a ON a.ROWID = m.sender
            WHERE m.ROWID = ?
            """, [id])
        guard let row = rows.first, let subject = row[0] as? String, !subject.isEmpty else { return nil }
        let sender = [(row[1] as? String), (row[2] as? String)].compactMap { $0 }.first { !$0.isEmpty }
        return sender.map { "\($0): \(subject)" }
    }
}
