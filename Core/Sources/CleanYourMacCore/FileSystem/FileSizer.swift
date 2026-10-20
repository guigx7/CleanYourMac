import Foundation

/// Mede bytes alocados em disco, sem seguir symlinks e contando cada inode uma vez.
public struct FileSizer: Sendable {
    public enum Mode: Sendable { case allocated, logical }
    public let mode: Mode

    public init(mode: Mode = .allocated) { self.mode = mode }

    private static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey,
                                                 .isDirectoryKey, .fileResourceIdentifierKey]

    private func size(_ v: URLResourceValues) -> Int64 {
        Int64((mode == .allocated ? v.totalFileAllocatedSize : v.fileSize) ?? 0)
    }

    public func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return 0 }
        if values.isSymbolicLink == true || values.isDirectory != true {
            return size(values)
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
            total += size(v)
        }
        return total
    }
}

/// Formatação de tamanhos exibida na interface (docs/re/specs/common.md §2):
/// base decimal, menor unidade KB, 1 casa decimal abaixo de 100 e nenhuma a partir de 100.
public enum SizeFormatter {
    private static let units: [(String, Double)] = [("KB", 1e3), ("MB", 1e6), ("GB", 1e9), ("TB", 1e12)]

    public static func string(_ bytes: Int64, locale: Locale) -> String {
        var index = units.lastIndex { Double(max(bytes, 0)) >= $0.1 } ?? 0
        var value = round(Double(max(bytes, 0)) / units[index].1)
        if value >= 1000, index < units.count - 1 {
            index += 1
            value = round(Double(bytes) / units[index].1)
        }
        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        number.usesGroupingSeparator = false
        number.minimumFractionDigits = 0
        number.maximumFractionDigits = value < 100 ? 1 : 0
        return "\(number.string(from: NSNumber(value: value)) ?? "0") \(units[index].0)"
    }

    /// Arredonda meio-para-par: 1 casa abaixo de 100, inteiro a partir de 100.
    private static func round(_ value: Double) -> Double {
        value < 99.95 ? (value * 10).rounded(.toNearestOrEven) / 10 : value.rounded(.toNearestOrEven)
    }
}
