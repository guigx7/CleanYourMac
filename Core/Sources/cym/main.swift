import Foundation
import CleanYourMacCore

// cym — análise do CleanYourMac pela linha de comando (paridade e diagnóstico).
//
//   cym scan [--groups a,b] [--json] [--paths] [--home DIR --user NOME]
//   cym clean --dry-run [--groups a,b] [--recommended]
//   cym apps [--json] [--no-network]   (módulo Aplicativos; só leitura)
//   cym performance [--json]           (módulo Desempenho; só leitura)
//   cym spacelens [caminho] [--json]   (Lupa de Espaço; só leitura: tempo, total e os maiores filhos)
//   cym clutter [pasta] [--json]       (Acúmulos; só leitura, sem a fototeca)
//
// Não existe limpeza de verdade pelo CLI: `clean` exige --dry-run.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"
if !args.isEmpty { args.removeFirst() }

@MainActor func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
@MainActor func has(_ flag: String) -> Bool { args.contains(flag) }

var context = ScanContext.current()
if let home = value("--home") {
    // Usado quando o cym roda como root para medir um usuário (análise privilegiada).
    let user = value("--user") ?? URL(fileURLWithPath: home).lastPathComponent
    context = ScanContext(root: context.root, home: URL(fileURLWithPath: home), userName: user,
                          preferredLanguages: context.preferredLanguages, now: Date(),
                          darwinUserCacheDir: value("--darwin").map { URL(fileURLWithPath: $0) })
}

let scanners = Registry.productionScanners()
var groups = Set(scanners.map(\.group))
if let list = value("--groups") {
    let requested = list.split(separator: ",").map(String.init)
    let unknown = requested.filter { GroupID(rawValue: $0) == nil }
    if !unknown.isEmpty { fail("grupos desconhecidos: \(unknown.joined(separator: ", "))") }
    groups = Set(requested.compactMap(GroupID.init(rawValue:)))
}

@MainActor func runScan() async throws -> ScanReport {
    for try await event in ScanEngine(scanners: scanners).scan(groups, context: context) {
        if case .finished(let report) = event { return report }
    }
    fail("análise não terminou")
}

/// Sem rede: nenhuma requisição sai (as fontes ficam sem resposta).
struct OfflineFetcher: HTTPFetcher {
    func get(_ url: URL, timeout: Duration) async throws -> Data { throw URLError(.notConnectedToInternet) }
}

switch command {
case "apps":
    let scan = has("--no-network") ? Registry.appsScan(fetcher: OfflineFetcher()) : Registry.appsScan()
    var appsReport: AppsReport?
    for try await event in scan.run(context) { if case .finished(let r) = event { appsReport = r } }
    guard let appsReport else { fail("análise não terminou") }
    let json = appsReport.parityJSON()
    if has("--json") {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        for item in appsReport.uninstaller {
            print(String(format: "%10@  %@", SizeFormatter.string(item.totalSize, locale: Locale(identifier: "pt-BR")), item.name))
        }
        print("filtros:", (json["filters"] as? [String: Int] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        print("atualizações:", appsReport.updates.updates.map { "\($0.name) \($0.installedVersion)→\($0.availableVersion) (\($0.source.rawValue))" },
              appsReport.updates.offline ? "[sem rede]" : "")
        print("sobras:", appsReport.leftovers.map { "\($0.name) \(SizeFormatter.string($0.totalSize, locale: Locale(identifier: "pt-BR")))" })
        print("instaladores:", appsReport.installers.map { "\($0.name) \(SizeFormatter.string($0.totalSize, locale: Locale(identifier: "pt-BR")))" })
    }
case "clutter":
    let folder = args.first { !$0.hasPrefix("--") }
    let started = Date()
    var clutterReport: ClutterReport?
    let threshold = ProcessInfo.processInfo.environment["CYM_SIMILAR_THRESHOLD"].flatMap(Int.init) ?? SimilarImageFinder.defaultThreshold
    for try await event in ClutterScan(similarThreshold: threshold).run(folder.map { .folder(URL(fileURLWithPath: $0)) } ?? .home) {
        if case .finished(let r) = event { clutterReport = r }
    }
    guard let clutterReport else { fail("análise não terminou") }
    if has("--json") {
        let data = try JSONSerialization.data(withJSONObject: clutterReport.parityJSON(), options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    }
    let br = Locale(identifier: "pt-BR")
    print(String(format: "%.1f s · %d arquivos para revisar", Date().timeIntervalSince(started), clutterReport.total))
    print("fundo do baú:", clutterReport.largeOld.map { "\($0.url.lastPathComponent) \(SizeFormatter.string($0.size, locale: br))" })
    print("duplicatas:", clutterReport.duplicates.count, "grupos ·", clutterReport.duplicates.prefix(5).map { "\($0.name) ×\($0.files.count)" })
    print("similares:", clutterReport.similar.count, "grupos")
    print("downloads:", clutterReport.downloads.map { "\($0.app.title) \(SizeFormatter.string($0.totalSize, locale: br))" })
    print("cartões:", clutterReport.tiles.map { "\($0.kind.rawValue) \($0.count) \(SizeFormatter.string($0.size, locale: br))" })
case "spacelens":
    let path = args.first { !$0.hasPrefix("--") }
    let start = Date()
    var lensReport: SpaceLensReport?
    for try await event in Registry.spaceLensScan().run(path.map { .folder(URL(fileURLWithPath: $0)) } ?? .disk) {
        if case .finished(let r) = event { lensReport = r }
    }
    guard let lensReport else { fail("análise não terminou") }
    if has("--json") {
        let folders = path == nil ? ["root": "", "users": "Users", "home": "Users/" + NSUserName()] : ["root": ""]
        let data = try JSONSerialization.data(withJSONObject: lensReport.parityJSON(folders: folders), options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    }
    let ptBR = Locale(identifier: "pt-BR")
    let node = lensReport.root
    print(String(format: "%.1f s · %d itens · %@ · %@ de %@ usados%@", Date().timeIntervalSince(start), node.items,
                 SizeFormatter.string(node.size, locale: ptBR), SizeFormatter.string(lensReport.used, locale: ptBR),
                 SizeFormatter.string(lensReport.capacity, locale: ptBR),
                 lensReport.purgeable.map { " · purgável " + SizeFormatter.string($0, locale: ptBR) } ?? ""))
    for c in node.children.prefix(15) {
        print(String(format: "%10@  %@%@", SizeFormatter.string(c.size, locale: ptBR), c.name, c.hasUnreadable ? "  [sem acesso a parte]" : ""))
    }
case "performance":
    var perfReport: PerformanceReport?
    for try await event in Registry.performanceScan().run(context) { if case .finished(let r) = event { perfReport = r } }
    guard let perfReport else { fail("análise não terminou") }
    if has("--json") {
        let data = try JSONSerialization.data(withJSONObject: perfReport.parityJSON(), options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        print("tarefas:", perfReport.tasks.map { $0.id.rawValue + ($0.detail.map { " (até \(SizeFormatter.string($0, locale: Locale(identifier: "pt-BR"))))" } ?? "") })
        print("itens de início:", perfReport.loginItems.map { $0.name + ($0.state == .disabled ? " [desativado]" : "") })
        print("em segundo plano:", perfReport.backgroundItems.map { $0.name + ($0.state == .disabled ? " [desativado]" : "") })
        print("capturas:", perfReport.snapshots.map(\.id))
    }
case "scan":
    let report = try await runScan()
    if has("--json") {
        var out: [String: Any] = ["tool": "cym", "version": CleanYourMacCore.version,
                                  "capturedAt": ISO8601DateFormatter().string(from: Date())]
        var groupsOut: [String: Any] = [:]
        for (g, result) in report.groups {
            groupsOut[g.rawValue] = [
                "totalBytes": result.totalSize,
                "items": result.items.map { item -> [String: Any] in
                    var entry: [String: Any] = ["name": item.name, "bytes": item.totalSize,
                                                "recommended": !item.leaves.isEmpty && item.leaves.allSatisfy { $0.isRecommended }]
                    if has("--paths") { entry["paths"] = item.leaves.compactMap { $0.url?.path } }
                    return entry
                },
            ]
        }
        out["groups"] = groupsOut
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print()
    } else {
        for g in GroupID.allCases where report.groups[g] != nil {
            let r = report.groups[g]!
            print("\(g.rawValue): \(SizeFormatter.string(r.totalSize, locale: Locale(identifier: "pt-BR"))) em \(r.items.count) itens")
        }
        print("total: \(SizeFormatter.string(report.totalSize, locale: Locale(identifier: "pt-BR")))")
    }

case "clean":
    guard has("--dry-run") else { fail("o cym só simula a limpeza: use --dry-run") }
    let report = try await runScan()
    let items = has("--recommended") ? report.recommendedItems() : report.groups.values.flatMap(\.items)
    let logDir = FileManager.default.temporaryDirectory.appendingPathComponent("cym-dryrun")
    let engine = CleanEngine(policies: Registry.policies(for: scanners, context: context),
                             privileged: AppleScriptPrivilegedRunner(), dryRun: true, log: CleanupLog(directory: logDir))
    for await event in engine.clean(items) {
        switch event {
        case .finished(let item, .success(let bytes)): print("removeria \(item.url?.path ?? item.name) (\(bytes) B)")
        case .finished(let item, .failure(let f)): print("RECUSADO \(item.url?.path ?? item.name): \(f.reason)")
        case .completed(let r): print("total: \(SizeFormatter.string(r.freedBytes, locale: Locale(identifier: "pt-BR"))), \(r.failed.count) recusados")
        case .started: break
        }
    }

default:
    print("""
    uso:
      cym scan [--groups a,b] [--json] [--paths] [--home DIR --user NOME [--darwin DIR]]
      cym clean --dry-run [--groups a,b] [--recommended]
    grupos: \(GroupID.allCases.map(\.rawValue).joined(separator: ", "))
    """)
}
