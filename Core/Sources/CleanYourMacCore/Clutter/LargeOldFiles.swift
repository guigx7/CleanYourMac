import Foundation
import UniformTypeIdentifiers

/// "Fundo do Baú": arquivos grandes da pasta pessoal, com filtros por tipo, tamanho e data de acesso
/// (docs/re/specs/clutter/large-old-files.md).
public enum LargeOldFiles {
    /// 50 MiB.
    public static let minimum: Int64 = 52_428_800

    public enum Kind: String, CaseIterable, Sendable { case archives, documents, pictures, videos, other }
    public enum SizeBucket: String, CaseIterable, Sendable { case small, average, huge }
    public enum AccessAge: String, CaseIterable, Sendable { case lastWeek, oneWeekAgo, oneMonthAgo, sixMonthsAgo, oneYearAgo }

    /// Do maior para o menor.
    public static func items(from files: [ClutterFile]) -> [ClutterFile] {
        files.filter { $0.size >= minimum }.sorted { $0.size != $1.size ? $0.size > $1.size : $0.url.path < $1.url.path }
    }

    public static func kind(_ file: ClutterFile) -> Kind {
        guard let type = file.type else { return .other }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .text) { return .documents }
        if type.conforms(to: .image) { return .pictures }
        if type.conforms(to: .movie) { return .videos }
        return .other
    }

    /// Unidades decimais: Pequeno < 500 MB ≤ Médio < 1 GB ≤ Imenso.
    public static func sizeBucket(_ size: Int64) -> SizeBucket {
        size >= 1_000_000_000 ? .huge : size >= 500_000_000 ? .average : .small
    }

    /// Faixas exclusivas a partir de hoje: 7 dias, 1 mês, 6 meses e 1 ano. Sem data conta como "há um ano".
    public static func age(of date: Date?, now: Date, calendar: Calendar = .current) -> AccessAge {
        guard let date else { return .oneYearAgo }
        func ago(_ c: Calendar.Component, _ n: Int) -> Date { calendar.date(byAdding: c, value: -n, to: now) ?? now }
        if date > ago(.day, 7) { return .lastWeek }
        if date > ago(.month, 1) { return .oneWeekAgo }
        if date > ago(.month, 6) { return .oneMonthAgo }
        if date > ago(.year, 1) { return .sixMonthsAgo }
        return .oneYearAgo
    }

    /// Cartão dos Resultados: os que não são abertos há mais de 365 dias.
    public static func tileFiles(_ items: [ClutterFile], now: Date) -> [ClutterFile] {
        items.filter { now.timeIntervalSince($0.accessed ?? .distantPast) > 31_536_000 }
    }
}
