import Foundation

/// Comparação de versões (docs/re/specs/apps/updater.md §Regra de comparação de versões).
public enum Version {
    /// `a` comparado com `b`; `nil` quando a comparação não é confiável.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        let x = normalize(a), y = normalize(b)
        guard isWellFormed(x), isWellFormed(y), sameShape(x, y) else { return nil }
        return compareSegments(segments(x), segments(y))
    }

    /// A versão disponível é mais nova que a instalada? `nil` quando não dá para saber.
    /// Pré-lançamento remoto só conta se o instalado também for pré-lançamento.
    public static func isUpdate(installed: String, available: String, homebrew: Bool = false) -> Bool? {
        let i = homebrew ? homebrewForm(installed) : installed
        let r = homebrew ? homebrewForm(available) : available
        if isPrerelease(normalize(r)) && !isPrerelease(normalize(i)) { return nil }
        guard let order = compare(r, i) else { return nil }
        return order == .orderedDescending
    }

    // MARK: - Normalização e forma

    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let first = t.first, first == "v" || first == "V", t.dropFirst().first?.isNumber == true { t.removeFirst() }
        return t
    }

    /// Homebrew: só o que vem antes da primeira vírgula, com `_` virando `.`.
    static func homebrewForm(_ s: String) -> String {
        String(s.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .replacingOccurrences(of: "_", with: ".")
    }

    private static let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.+-")

    static func isWellFormed(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.lowercased() != "latest"
            && s.contains(where: \.isNumber)
            && s.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Versão por data × semântica (8+ dígitos no começo de um lado só, ou primeiro número 100× maior).
    static func sameShape(_ a: String, _ b: String) -> Bool {
        let na = leadingNumber(a), nb = leadingNumber(b)
        let dateA = (na?.count ?? 0) >= 8, dateB = (nb?.count ?? 0) >= 8
        if dateA != dateB { return false }
        if let na, let nb, let va = Double(na), let vb = Double(nb) {
            if va > 100 * max(vb, 1) && va > vb || vb > 100 * max(va, 1) && vb > va { return false }
        }
        return true
    }

    private static func leadingNumber(_ s: String) -> String? {
        let digits = s.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    private static let prereleaseMarkers = ["alpha", "beta", "rc", "preview", "pre", "dev", "nightly", "canary"]

    static func isPrerelease(_ s: String) -> Bool {
        let lower = s.lowercased()
        for case .text(let t) in segments(lower) {
            if prereleaseMarkers.contains(where: { t.contains($0) }) { return true }
            if t == "b" || t == "a" { return true }
        }
        return false
    }

    // MARK: - Segmentos (mesmo algoritmo do comparador padrão do Sparkle)

    enum Segment: Equatable {
        case number(String), text(String), period
    }

    static func segments(_ s: String) -> [Segment] {
        var out: [Segment] = []
        var current = ""
        var currentIsNumber: Bool?
        func flush() {
            guard let isNumber = currentIsNumber else { return }
            out.append(isNumber ? .number(current) : .text(current))
            current = ""
            currentIsNumber = nil
        }
        for ch in s {
            if ch == "." {
                flush()
                out.append(.period)
            } else {
                let isNumber = ch.isASCII && ch.isNumber
                if currentIsNumber != nil && currentIsNumber != isNumber { flush() }
                currentIsNumber = isNumber
                current.append(ch)
            }
        }
        flush()
        return out
    }

    /// Ordem entre tipos diferentes: número > ponto > texto.
    private static func rank(_ s: Segment) -> Int {
        switch s {
        case .number: 2
        case .period: 1
        case .text: 0
        }
    }

    static func compareSegments(_ a: [Segment], _ b: [Segment]) -> ComparisonResult {
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case (.number(let p), .number(let q)):
                let r = compareNumbers(p, q)
                if r != .orderedSame { return r }
            case (.text(let p), .text(let q)):
                if p != q { return p < q ? .orderedAscending : .orderedDescending }
            case (.period, .period):
                continue
            default:
                return rank(x) < rank(y) ? .orderedAscending : .orderedDescending
            }
        }
        if a.count == b.count { return .orderedSame }
        // O mais longo vence, salvo quando o excedente começa com texto (1.0 > 1.0a).
        let longerIsA = a.count > b.count
        let extra = longerIsA ? a[b.count] : b[a.count]
        if case .text = extra { return longerIsA ? .orderedAscending : .orderedDescending }
        return longerIsA ? .orderedDescending : .orderedAscending
    }

    /// Números grandes (mais de 18 dígitos) comparados como texto alinhado à direita.
    private static func compareNumbers(_ p: String, _ q: String) -> ComparisonResult {
        let a = String(p.drop(while: { $0 == "0" })), b = String(q.drop(while: { $0 == "0" }))
        if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }
}
