import Foundation

/// Um item de um appcast do Sparkle (docs/re/specs/apps/updater.md §F2).
public struct AppcastItem: Hashable, Sendable {
    /// `sparkle:version` (comparada com `CFBundleVersion`).
    public var version: String
    /// `sparkle:shortVersionString`, só para exibição.
    public var shortVersion: String?
    public var minimumSystemVersion: String?
    public var maximumSystemVersion: String?
    public var hardwareRequirements: [String] = []
    public var channel: String?
    public var os: String?
    public var date: Date?
    /// Novidades em texto puro (HTML removido).
    public var notes: String?
    public var notesURL: URL?
    public var link: URL?
    public var downloadURL: URL?
    public var length: Int64?
    public var edSignature: String?
    public var installationType: String?
    public var isInformational = false
    public var isCritical = false
}

public enum AppcastError: Error, Sendable {
    case malformed(String)
}

public enum AppcastParser {
    /// Itens com `sparkle:version` (elemento no Sparkle 2 ou atributo do `enclosure` no Sparkle 1).
    public static func parse(_ data: Data) throws -> [AppcastItem] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw AppcastError.malformed(parser.parserError?.localizedDescription ?? "xml")
        }
        return delegate.items.compactMap { $0.version.isEmpty ? nil : $0 }
    }

    /// O item válido de maior versão para este sistema (sem canal, sem `sparkle:os` estranho, na faixa do macOS).
    public static func best(_ items: [AppcastItem], systemVersion: OperatingSystemVersion, arch: String) -> AppcastItem? {
        let valid = items.filter { item in
            guard item.channel == nil, item.os == nil || item.os == "macos" else { return false }
            if let min = item.minimumSystemVersion, compareOS(systemVersion, min) == .orderedAscending { return false }
            if let max = item.maximumSystemVersion, compareOS(systemVersion, max) == .orderedDescending { return false }
            if !item.hardwareRequirements.isEmpty, !item.hardwareRequirements.contains(arch) { return false }
            return item.downloadURL != nil || item.isInformational
        }
        return valid.max { a, b in Version.compare(a.version, b.version) == .orderedAscending }
    }

    static func compareOS(_ os: OperatingSystemVersion, _ s: String) -> ComparisonResult {
        let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return Version.compare(current, s) ?? .orderedSame
    }

    /// Remove tags e entidades HTML das novidades.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return rfc822.lazy.compactMap { $0.date(from: t) }.first
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []
        private var current: AppcastItem?
        private var text = ""
        private var inDeltas = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "item":
                current = AppcastItem(version: "")
            case "sparkle:deltas":
                inDeltas = true
            case "enclosure" where !inDeltas:
                guard var item = current else { break }
                item.downloadURL = attributes["url"].flatMap(URL.init(string:))
                item.length = attributes["length"].flatMap { Int64($0) }
                item.edSignature = attributes["sparkle:edSignature"]
                item.os = attributes["sparkle:os"]
                if let type = attributes["sparkle:installationType"] { item.installationType = type }
                if item.version.isEmpty, let v = attributes["sparkle:version"] { item.version = v }
                if item.shortVersion == nil { item.shortVersion = attributes["sparkle:shortVersionString"] }
                current = item
            case "sparkle:informationalUpdate":
                current?.isInformational = true
            case "sparkle:criticalUpdate":
                current?.isCritical = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { text = "" }
            guard current != nil else { return }
            switch name {
            case "item":
                if let item = current { items.append(item) }
                current = nil
            case "sparkle:deltas":
                inDeltas = false
            case "sparkle:version" where !value.isEmpty:
                current?.version = value
            case "sparkle:shortVersionString" where !value.isEmpty:
                current?.shortVersion = value
            case "sparkle:minimumSystemVersion":
                current?.minimumSystemVersion = value
            case "sparkle:maximumSystemVersion":
                current?.maximumSystemVersion = value
            case "sparkle:hardwareRequirements":
                current?.hardwareRequirements = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "sparkle:channel":
                current?.channel = value.isEmpty ? nil : value
            case "sparkle:installationType":
                current?.installationType = value
            case "pubDate":
                current?.date = AppcastParser.date(value)
            case "description" where !value.isEmpty:
                current?.notes = AppcastParser.plainText(value)
            case "sparkle:releaseNotesLink":
                current?.notesURL = URL(string: value)
            case "link":
                current?.link = URL(string: value)
            default:
                break
            }
        }
    }
}
