import Foundation

/// Mede bytes alocados em disco, sem seguir symlinks e contando cada inode uma vez.
public struct FileSizer: Sendable {
    public init() {}

    private static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isSymbolicLinkKey,
                                                 .isDirectoryKey, .fileResourceIdentifierKey]

    public func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return 0 }
        if values.isSymbolicLink == true || values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        var seen = Set<AnyHashable>()
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Self.keys,
                                               options: [], errorHandler: { _, _ in true })
        while let child = e?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: Set(Self.keys)), v.isDirectory != true || v.isSymbolicLink == true else { continue }
            if let id = v.fileResourceIdentifier as? AnyHashable {
                guard seen.insert(id).inserted else { continue }
            }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Formatação de tamanhos exibida na interface.
public enum SizeFormatter {
    public static func string(_ bytes: Int64, locale: Locale) -> String {
        if bytes == 0 {
            return "0 KB"
        }
        // A interface usa "KB" maiúsculo, como o Finder exibe em pt-BR e en.
        return bytes.formatted(.byteCount(style: .file).locale(locale))
            .replacingOccurrences(of: "kB", with: "KB")
    }
}
