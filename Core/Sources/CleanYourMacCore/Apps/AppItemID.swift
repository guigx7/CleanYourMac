import Foundation

/// Ids dos itens do módulo Aplicativos: dizem a que app (e operação) cada folha pertence.
/// Separador U+001E entre partes (não aparece em caminhos nem em bundle IDs).
public enum AppItemID {
    public enum Mode: String, Sendable {
        case uninstall = "appUninstall"
        case reset = "appReset"
        case leftovers = "appLeftovers"
    }

    static let sep = "\u{1E}"

    /// Folha de um app (`appID` = `AppRecord.id`, "bundleID|caminho").
    public static func leaf(mode: Mode, appID: String, path: String) -> String {
        "\(mode.rawValue):\(appID)\(sep)\(path)"
    }

    /// A folha do próprio bundle do app (removida por último).
    public static func bundle(mode: Mode, appID: String) -> String {
        "\(mode.rawValue):\(appID)\(sep)bundle"
    }

    public static func leftover(bundleID: String, path: String) -> String {
        "\(Mode.leftovers.rawValue):\(bundleID)\(sep)\(path)"
    }

    public static func mode(of id: String) -> Mode? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        return Mode(rawValue: String(id[..<colon]))
    }

    /// "bundleID|caminho" (ou só o bundle ID, nas sobras).
    public static func appID(of id: String) -> String? {
        guard mode(of: id) != nil, let colon = id.firstIndex(of: ":") else { return nil }
        let rest = id[id.index(after: colon)...]
        return rest.range(of: sep).map { String(rest[..<$0.lowerBound]) } ?? String(rest)
    }

    /// Bundle ID do app dono.
    public static func owner(of id: String) -> String? {
        appID(of: id).map { String($0.split(separator: "|", maxSplits: 1).first ?? "") }.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func isBundle(_ id: String) -> Bool {
        mode(of: id) != nil && id.hasSuffix(sep + "bundle")
    }
}
