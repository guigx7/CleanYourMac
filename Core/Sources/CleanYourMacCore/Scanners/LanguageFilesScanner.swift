import Foundation
import Carbon

/// Pastas `.lproj` de idiomas que o usuário não usa, agrupadas por idioma (docs/re/specs/language-files.md).
public struct LanguageFilesScanner: ScopedScanner {
    public let group = GroupID.languageFiles
    private let inventory: any AppInventory
    private let keyboardLanguages: @Sendable () -> [String]
    private let sizer = FileSizer()

    public init(inventory: any AppInventory = UserAppsInventory(),
                keyboardLanguages: @escaping @Sendable () -> [String] = LanguageFilesScanner.enabledKeyboardLanguages) {
        self.inventory = inventory
        self.keyboardLanguages = keyboardLanguages
    }

    /// Idioma principal (o primeiro da lista) de cada fonte de entrada de teclado habilitada.
    /// Um teclado latino lista dezenas de idiomas; a baseline só fecha considerando o primeiro.
    public static let enabledKeyboardLanguages: @Sendable () -> [String] = {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.flatMap { source -> [String] in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
            return Array(((Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]) ?? []).prefix(1))
        }
    }

    private func apps(_ ctx: ScanContext) -> [InstalledApp] {
        inventory.apps(ctx).filter { UniversalBinariesScanner.isInScope($0.url, ctx) && UniversalBinariesScanner.eligible($0, ctx) }
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(items: apps(context).map(\.url))
    }

    /// Código canônico de uma pasta `<x>.lproj`.
    static func code(_ lproj: URL) -> String {
        let raw = lproj.deletingPathExtension().lastPathComponent
        let fixed = ["ua": "uk", "jp": "ja"][raw.lowercased()] ?? raw
        let canonical = Locale.canonicalLanguageIdentifier(from: fixed)
        return canonical.isEmpty ? raw : canonical
    }

    static func primary(_ code: String) -> String {
        String(code.lowercased().split(separator: "-").first ?? "")
    }

    static func isProtected(_ code: String, userPrimaries: Set<String>) -> Bool {
        let c = code.lowercased()
        if ["en", "english", "base", "default", "empty", "."].contains(c) || c.hasPrefix("en-") { return true }
        return userPrimaries.contains(primary(c))
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let primaries = Set((context.preferredLanguages + keyboardLanguages()).map {
            Self.primary(Locale.canonicalLanguageIdentifier(from: $0))
        })
        var byCode: [String: [JunkItem]] = [:]
        var order: [String] = []
        for app in apps(context) {
            try Task.checkCancellation()
            report(ScanProgress(group: group, currentPath: app.url.path, bytesFound: 0))
            let sealed = Self.sealedLprojs(app.url)
            var perCode: [String: [URL]] = [:]
            for resources in Self.resourceFolders(app.url) {
                let lprojs = Self.lprojFolders(resources)
                let unprotected = lprojs.filter { !Self.isProtected(Self.code($0), userPrimaries: primaries) }
                let distinct = Set(unprotected.map(Self.code))
                // Nunca deixar uma pasta Resources sem nenhum idioma.
                if !lprojs.isEmpty, lprojs.count == distinct.count, distinct.count == unprotected.count { continue }
                for l in unprotected where !sealed.contains(PathPolicy.realPath(l.path)) && Self.onlyStrings(l) {
                    perCode[Self.code(l), default: []].append(l)
                }
            }
            for (code, lprojs) in perCode {
                let size = lprojs.reduce(Int64(0)) { $0 + sizer.allocatedSize(of: $1) }
                if byCode[code] == nil { order.append(code) }
                byCode[code, default: []].append(JunkItem(id: "languageFiles:\(code):\(app.url.path)", group: group,
                                                          name: app.name, url: app.url, size: size, icon: .app(app.url),
                                                          removal: .removeLocalizations(bundle: app.url, lprojs: lprojs)))
            }
        }
        return order.map { code in
            JunkItem(id: "languageFiles:\(code)", group: group, name: Locale.current.localizedString(forIdentifier: code) ?? code,
                     detail: code, url: nil, size: 0, icon: .symbol("globe"), children: byCode[code] ?? [])
        }
    }

    /// Pastas chamadas `Resources` (reais, não links), sem descer em `.lproj`. Um `.wdgt` é a própria pasta.
    static func resourceFolders(_ app: URL) -> [URL] {
        if app.pathExtension == "wdgt" { return [app] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let e = FileManager.default.enumerator(at: app, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        var out: [URL] = []
        while let u = e?.nextObject() as? URL {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true else { continue }
            if u.pathExtension.lowercased() == "lproj" { e?.skipDescendants(); continue }
            if u.lastPathComponent.lowercased() == "resources" { out.append(u) }
        }
        return out
    }

    static func lprojFolders(_ resources: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
            .filter { u in
                guard u.pathExtension.lowercased() == "lproj",
                      let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
                return v.isDirectory == true && v.isSymbolicLink != true
            }
            .sorted { $0.path < $1.path }
    }

    /// Só `.strings`/`.stringsdict` (recursivo, inclusive ocultos); pasta vazia também vale.
    static func onlyStrings(_ lproj: URL) -> Bool {
        let e = FileManager.default.enumerator(at: lproj, includingPropertiesForKeys: [.isRegularFileKey], options: [], errorHandler: { _, _ in true })
        while let u = e?.nextObject() as? URL {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  ["strings", "stringsdict"].contains(u.pathExtension) else { return false }
        }
        return true
    }

    /// `.lproj` seladas como obrigatórias em algum `CodeResources` do bundle.
    static func sealedLprojs(_ app: URL) -> Set<String> {
        let e = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true })
        var out = Set<String>()
        while let u = e?.nextObject() as? URL {
            guard u.lastPathComponent == "CodeResources", let data = try? Data(contentsOf: u),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let base = u.deletingLastPathComponent().deletingLastPathComponent()
            for key in ["files", "files2"] {
                for (path, value) in (dict[key] as? [String: Any]) ?? [:] {
                    guard let r = path.range(of: ".lproj") else { continue }
                    let v = value as? [String: Any]
                    if v?["optional"] as? Bool == true { continue }
                    out.insert(PathPolicy.realPath(base.appendingPathComponent(String(path[..<r.upperBound])).path))
                    if let target = v?["symlink"] as? String, let tr = target.range(of: ".lproj") {
                        let dir = base.appendingPathComponent(path).deletingLastPathComponent()
                        out.insert(PathPolicy.realPath(dir.appendingPathComponent(String(target[..<tr.upperBound])).path))
                    }
                }
            }
        }
        return out
    }
}
